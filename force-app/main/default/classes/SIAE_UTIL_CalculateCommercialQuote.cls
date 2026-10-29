/**
 * @description       : Recupera il record di Accordo Commerciale e calcola 
 * 						eventuale riduzione e quota associativa
 * @author            : Rondinella Francesco - francesco.rondinella@nttdata.com
 * @group             : NTT Data
 * @last modified on  : 07-15-2026
**/
public with sharing class SIAE_UTIL_CalculateCommercialQuote {
    public class CommercialAgreementIndex {
        private Map<String, List<SIAE_AccordoCommerciale__c>> agreementsByKey =
            new Map<String, List<SIAE_AccordoCommerciale__c>>();

        public void add(SIAE_AccordoCommerciale__c agreement) {
            if (agreement == null) {
                return;
            }

            String key = buildKey(
                agreement.SIAE_CodiceAccordoCommerciale__c,
                agreement.SIAE_CodiceDiIncrocio__c
            );
            if (String.isBlank(key)) {
                return;
            }

            if (!agreementsByKey.containsKey(key)) {
                agreementsByKey.put(key, new List<SIAE_AccordoCommerciale__c>());
            }
            agreementsByKey.get(key).add(agreement);
        }

        public SIAE_AccordoCommerciale__c resolve(String key, Date effectiveDate) {
            if (String.isBlank(key) || !agreementsByKey.containsKey(key)) {
                return null;
            }

            for (SIAE_AccordoCommerciale__c agreement : agreementsByKey.get(key)) {
                if (isValidOn(agreement, effectiveDate)) {
                    return agreement;
                }
            }
            return null;
        }

        public Boolean isEmpty() {
            return agreementsByKey.isEmpty();
        }
    }

    private static String buildKey(String commercialCode, String intersectionCode) {
        if (String.isBlank(commercialCode) || String.isBlank(intersectionCode)) {
            return null;
        }
        return commercialCode + '|' + intersectionCode;
    }

    private static Boolean isValidOn(SIAE_AccordoCommerciale__c agreement, Date effectiveDate) {
        if (agreement == null) {
            return false;
        }
        if (effectiveDate == null) {
            return true;
        }

        Date validFrom = RCAValueConverter.asDate(agreement.SIAE_DataInizioValidita__c);
        Date validTo = RCAValueConverter.asDate(agreement.SIAE_DataFineValidita__c);

        return (validFrom == null || effectiveDate >= validFrom) &&
               (validTo == null || effectiveDate <= validTo);
    }
    public class CalculationResult {
        public Id accordoId;
        public String codiceAccordoCommerciale;
        public String codiceIncrocio;

        public Decimal compensoTotaleInput;
        public Decimal riduzioneCompensoBasePercent;
        public Decimal compensoTotaleScontato;

        public String voceQuota;
        public Decimal quotaUnitaria;
        public Decimal quotaUnitariaTotale;

        public Decimal percentualeQuotaSuNettoDDA;
        public Decimal quotaSuNettoDDAValue;

        public Decimal minimoQuota;
        public Decimal minimoQuotaTotale;

        public Decimal quota;
        public String logicaApplicata;
        
        public Decimal percentualeScontoDC;
    }

    public static CalculationResult calculateAccordoCommerciale(String key, Map<String, SIAE_AccordoCommerciale__c> mapKeyCommercialAgreement, Decimal numberDevicesLC, Decimal compensoTotale) {
        CalculationResult result = new CalculationResult();
        if (mapKeyCommercialAgreement.keySet().isEmpty() || !mapKeyCommercialAgreement.keySet().contains(key)) {
            return result;
        }


        SIAE_AccordoCommerciale__c accordo = mapKeyCommercialAgreement.get(key);

        
        result.accordoId = accordo.Id;
        result.codiceAccordoCommerciale = accordo.SIAE_CodiceAccordoCommerciale__c;
        result.codiceIncrocio = accordo.SIAE_CodiceDiIncrocio__c;
        result.compensoTotaleInput = compensoTotale;
        result.percentualeScontoDC = accordo.SIAE_PercentualeScontoDC__c;

        Decimal compensoScontato = compensoTotale;

        // 1) Recupero e stampa riduzione compenso base
        Decimal riduzioneCompensoBase = accordo.SIAE_RiduzioneCompensoBase__c;
        result.riduzioneCompensoBasePercent = riduzioneCompensoBase;

        // 2) Applico la riduzione compenso base, se presente
        if (riduzioneCompensoBase != null) {
            compensoScontato = compensoTotale * (1 - riduzioneCompensoBase);
        }

        result.compensoTotaleScontato = compensoScontato;

        // 3) Controllo voce quota
        if (String.isNotBlank(accordo.SIAE_VoceQuota__c)) {
            result.voceQuota = accordo.SIAE_VoceQuota__c;

            // Strada 1: quota unitaria
            if (accordo.SIAE_QuotaUnitaria__c != null) {
                Decimal quotaUnitaria = accordo.SIAE_QuotaUnitaria__c;
                Decimal quotaUnitariaTotale = quotaUnitaria * numberDevicesLC;

                result.quotaUnitaria = quotaUnitaria;
                result.quotaUnitariaTotale = quotaUnitariaTotale;
                result.quota = quotaUnitariaTotale;
                result.logicaApplicata = 'QUOTA_UNITARIA';
            }
            // Strada 2: quota su netto DDA
            else if (accordo.SIAE_PercentualeQuotaSuNettoDDA__c != null) {
                Decimal percentualeQuotaSuNettoDDA = accordo.SIAE_PercentualeQuotaSuNettoDDA__c;
                Decimal quotaSuNettoDDAValue = compensoScontato * percentualeQuotaSuNettoDDA;

                result.percentualeQuotaSuNettoDDA = percentualeQuotaSuNettoDDA;
                result.quotaSuNettoDDAValue = quotaSuNettoDDAValue;

                // Controllo minimo quota
                if (accordo.SIAE_MinimoQuota__c != null) {
                    Decimal minimoQuota = accordo.SIAE_MinimoQuota__c;
                    Decimal minimoQuotaTotale = minimoQuota * numberDevicesLC;

                    result.minimoQuota = minimoQuota;
                    result.minimoQuotaTotale = minimoQuotaTotale;

                    Decimal valoreScelto = Math.max(minimoQuotaTotale, quotaSuNettoDDAValue);                   
                    result.quota = valoreScelto;
                    result.logicaApplicata = 'QUOTA_SU_NETTO_DDA_CON_MINIMO';
                } else {
                    result.quota = compensoScontato * percentualeQuotaSuNettoDDA;
                    result.logicaApplicata = 'QUOTA_SU_NETTO_DDA';
                }
            } else {
                result.logicaApplicata = 'VOCE_QUOTA_PRESENTE_MA_NESSUN_VALORE_ASSOCIATO';

            }
        } else {
            result.logicaApplicata = 'NESSUNA_VOCE_QUOTA';
        }       
        return result;
    }

    public static CommercialAgreementIndex loadCommercialAgreements(
        Set<String> setOfCommercialAgreement,
        Set<String> setOfProductFamily
    ) {
        CommercialAgreementIndex index = new CommercialAgreementIndex();
        if (setOfCommercialAgreement == null || setOfCommercialAgreement.isEmpty() ||
            setOfProductFamily == null || setOfProductFamily.isEmpty()) {
            return index;
        }

        for (SIAE_AccordoCommerciale__c commercialAgreement : [
            SELECT Id, Name, SIAE_CodiceAccordoCommerciale__c, SIAE_CodiceDiIncrocio__c,
                   SIAE_RiduzioneCompensoBase__c, SIAE_VoceQuota__c,
                   SIAE_PercentualeQuotaSuNettoDDA__c, SIAE_QuotaUnitaria__c,
                   SIAE_MinimoQuota__c, SIAE_PercentualeScontoDC__c,
                   SIAE_DataInizioValidita__c, SIAE_DataFineValidita__c
            FROM SIAE_AccordoCommerciale__c
            WHERE SIAE_CodiceAccordoCommerciale__c IN :setOfCommercialAgreement
              AND SIAE_CodiceDiIncrocio__c IN :setOfProductFamily
            ORDER BY SIAE_DataInizioValidita__c DESC NULLS LAST
        ]) {
            index.add(commercialAgreement);
        }
        return index;
    }

    /*
     * Backward-compatible API for existing callers/tests. If multiple temporal
     * versions exist for the same key, this method intentionally returns the
     * first loaded version. New pricing flows must use CommercialAgreementIndex.
     */
    public static Map<String, SIAE_AccordoCommerciale__c> getMapCommercialAgreement(
        Set<String> setOfCommercialAgreement,
        Set<String> setOfProductFamily
    ) {
        Map<String, SIAE_AccordoCommerciale__c> result = new Map<String, SIAE_AccordoCommerciale__c>();
        if (setOfCommercialAgreement == null || setOfCommercialAgreement.isEmpty() ||
            setOfProductFamily == null || setOfProductFamily.isEmpty()) {
            return result;
        }

        for (SIAE_AccordoCommerciale__c agreement : [
            SELECT Id, Name, SIAE_CodiceAccordoCommerciale__c, SIAE_CodiceDiIncrocio__c,
                   SIAE_RiduzioneCompensoBase__c, SIAE_VoceQuota__c,
                   SIAE_PercentualeQuotaSuNettoDDA__c, SIAE_QuotaUnitaria__c,
                   SIAE_MinimoQuota__c, SIAE_PercentualeScontoDC__c,
                   SIAE_DataInizioValidita__c, SIAE_DataFineValidita__c
            FROM SIAE_AccordoCommerciale__c
            WHERE SIAE_CodiceAccordoCommerciale__c IN :setOfCommercialAgreement
              AND SIAE_CodiceDiIncrocio__c IN :setOfProductFamily
            ORDER BY SIAE_DataInizioValidita__c DESC NULLS LAST
        ]) {
            String key = buildKey(agreement.SIAE_CodiceAccordoCommerciale__c, agreement.SIAE_CodiceDiIncrocio__c);
            if (String.isNotBlank(key) && !result.containsKey(key)) {
                result.put(key, agreement);
            }
        }
        return result;
    }
}