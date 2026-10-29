/**
 * @description       : Recupera il record di Accordo Commerciale e calcola 
 * 						eventuale riduzione e quota associativa
 * @author            : Rondinella Francesco - francesco.rondinella@nttdata.com
 * @group             : NTT Data
 * @last modified on  : 04-15-2026
**/

public with sharing class SIAE_CalcoloAccordoCommerciale {

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

    public static CalculationResult calculateAccordoCommerciale(String codiceAccordoCommerciale, String codiceIncrocio, Decimal numberDevicesLC,Decimal compensoTotale) {
        List<SIAE_AccordoCommerciale__c> accordi = new List<SIAE_AccordoCommerciale__c>([
            SELECT Id, Name, SIAE_CodiceAccordoCommerciale__c, SIAE_CodiceDiIncrocio__c, SIAE_RiduzioneCompensoBase__c, SIAE_VoceQuota__c, SIAE_PercentualeQuotaSuNettoDDA__c, 
                    SIAE_QuotaUnitaria__c, SIAE_MinimoQuota__c, SIAE_PercentualeScontoDC__c
            FROM SIAE_AccordoCommerciale__c
            WHERE SIAE_CodiceAccordoCommerciale__c = :codiceAccordoCommerciale AND SIAE_CodiceDiIncrocio__c = :codiceIncrocio
        ]);

        if (accordi.isEmpty()) {
            throw new AuraHandledException(
                'Nessun accordo commerciale trovato per codice accordo commerciale = '
                + codiceAccordoCommerciale +
                ' e codice incrocio = ' + codiceIncrocio
            );
        }

        if (accordi.size() > 1) {
            throw new AuraHandledException(
                'Trovati più record di accordo commerciale per codice accordo commerciale = '
                + codiceAccordoCommerciale +
                ' e codice incrocio = ' + codiceIncrocio
            );
        }

        SIAE_AccordoCommerciale__c accordo = accordi[0];

        CalculationResult result = new CalculationResult();
        result.accordoId = accordo.Id;
        result.codiceAccordoCommerciale = codiceAccordoCommerciale;
        result.codiceIncrocio = codiceIncrocio;
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
}