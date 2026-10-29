/**
 * @description       : Dominio di accesso e risoluzione temporale di SIAE_ConfigurazionePricing__c per MdA.
 *                      La configurazione applicabile e' determinata per Product2 + EffectiveFrom della singola riga.
 * @group             : NTT Data
 * @last modified on  : 10-28-2026
 **/
public with sharing class MdAPricingConfiguration {

    public class ConfigurationIndex {
        private Map<Id, List<SIAE_ConfigurazionePricing__c>> byProduct;

        private ConfigurationIndex(Map<Id, List<SIAE_ConfigurazionePricing__c>> byProduct) {
            this.byProduct = byProduct == null
                ? new Map<Id, List<SIAE_ConfigurazionePricing__c>>()
                : byProduct;
        }

        public SIAE_ConfigurazionePricing__c resolve(Id productId, Date effectiveDate) {
            System.debug(
                '### MDA CONFIG RESOLVE productId=' + productId +
                ' effectiveDate=' + effectiveDate
            );


            if (productId == null || effectiveDate == null || !byProduct.containsKey(productId)) {
                return null;
            }

            for (SIAE_ConfigurazionePricing__c conf : byProduct.get(productId)) {
                System.debug(
                '### MDA CONFIG CHECK id=' + conf.Id +
                ' start=' + conf.SIAE_DataInizioValidita__c +
                ' end=' + conf.SIAE_DataFineValidita__c
            );
                Date validFromDate = conf.SIAE_DataInizioValidita__c == null
                    ? null
                    : conf.SIAE_DataInizioValidita__c.dateGMT();
                Date validToDate = conf.SIAE_DataFineValidita__c == null
                    ? null
                    : conf.SIAE_DataFineValidita__c.dateGMT();

                Boolean validFrom = validFromDate == null || validFromDate <= effectiveDate;
                Boolean validTo = validToDate == null || validToDate >= effectiveDate;

                if (validFrom && validTo) {
                    System.debug(
                    '### MDA CONFIG SELECTED=' + conf.Id
                    );
                    return conf;
                }
            }
            System.debug(
    '### MDA CONFIG NOT FOUND productId=' + productId +
    ' effectiveDate=' + effectiveDate
);
            return null;
        }
    }

    public static ConfigurationIndex load(Set<Id> productIds) {
        Map<Id, List<SIAE_ConfigurazionePricing__c>> byProduct =
            new Map<Id, List<SIAE_ConfigurazionePricing__c>>();

        if (productIds == null || productIds.isEmpty()) {
            return new ConfigurationIndex(byProduct);
        }

        for (SIAE_ConfigurazionePricing__c conf : [
            SELECT Id, Name, SIAE_Product2__c, SIAE_Attivo__c,
                   SIAE_UsaDefaultTypeCoverage__c, SIAE_UsaCoeffStagionalita__c,
                   SIAE_UsaMaggiorazioneEsterna__c, SIAE_UsaMaggiorazioneMQ__c,
                   SIAE_UsaMaggiorazioneDipendenti__c, SIAE_UsaMaggiorazioneTV40__c,
                   SIAE_DefaultTypeCoverageValue__c, SIAE_CoeffStag_Annuale__c,
                   SIAE_CoeffStag_Semestrale__c, SIAE_CoeffStag_Trimestrale__c,
                   SIAE_CoeffStag_Mensile__c, SIAE_AreeEsterne_ValoreNo__c,
                   SIAE_AreeEsterne_ValoreFino50__c, SIAE_AreeEsterne_ValoreOltre50__c,
                   SIAE_MQ_SogliaBase__c, SIAE_MQ_Tranche__c, SIAE_MQ_IncrementoPerTranche__c,
                   SIAE_MQ_CoeffBase__c, SIAE_Dip_SogliaBase__c, SIAE_Dip_Tranche__c,
                   SIAE_Dip_ImportoRadio__c, SIAE_Dip_ImportoAudio__c, SIAE_Dip_ImportoVideo__c,
                   SIAE_TV40_Coefficiente__c, SIAE_DifferenziaAltoparlanti__c,
                   SIAE_UsaCompensoUnico__c, SIAE_UsaDividiCompenso__c,
                   SIAE_DividiCompensoValore__c, SIAE_NuovaStruttura_Valore__c,
                   SIAE_LicenzaRistorazione_Valore__c, SIAE_UsaFlat__c,
                   SIAE_AggiungiAFLAT__c, SIAE_EscludiFlatAudio__c,
                   SIAE_DataInizioValidita__c, SIAE_DataFineValidita__c
            FROM SIAE_ConfigurazionePricing__c
            WHERE SIAE_Attivo__c = true
            AND SIAE_Product2__c IN :productIds
            ORDER BY SIAE_Product2__c, SIAE_DataInizioValidita__c DESC
        ]) {
            if (conf.SIAE_Product2__c == null) {
                continue;
            }
            if (!byProduct.containsKey(conf.SIAE_Product2__c)) {
                byProduct.put(conf.SIAE_Product2__c, new List<SIAE_ConfigurazionePricing__c>());
            }
            byProduct.get(conf.SIAE_Product2__c).add(conf);
        }

        return new ConfigurationIndex(byProduct);
    }
}