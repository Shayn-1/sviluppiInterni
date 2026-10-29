/**
 * @description       : PreHook del Procedure Plan SIAE.
 *                      Viene eseguito PRIMA della Pricing Procedure unica nel contesto
 *                      della SalesTransaction (Place Order / ordine reale).
 *
 *                      Legge il context con RCAContextReader, calcola i valori derivati
 *                      e li riscrive sul context con RCAContextWriter.
 *
 * @author            : Francesco Rondinella
 * @group             : NTT Data - SIAE
 * @last modified on  : 10-29-2026
 * @last modified by  : Domenico Del Prete - domenico.delprete@nttdata.com
**/
global class SIAE_PREH_PricingMdAPlan implements RevSignaling.SignalingApexProcessor {

    private static final String DEBUG_VERSION = 'SIAE_PreHook_V1';
    private static final String CATALOG_CODE = 'MDA';
    private static final String FIELD_SELLING_MODEL = 'ProductSellingModel';
    private static final String FIELD_ATTRIBUTE_VALUE = 'AttributeValue';
    private static final String FIELD_HAS_AUDIO = 'SIAE_HasAudio__c';
    private static final String FIELD_HAS_RADIO = 'SIAE_HasRadio__c';
    private static final String FIELD_HAS_VIDEO = 'SIAE_HasVideo__c';

    private static final String ATTR_QTA = 'SIAE-ATTR-QTA';
    private static final String FIELD_COEFF_MAGG_MQ = 'SIAE_CoeffMaggiorazioneMQ__c';
    private static final String FIELD_MAGG_DIP_RADIO = 'SIAE_CoeffMaggiorazioneDipendentiRadio__c';
    private static final String FIELD_MAGG_DIP_AUDIO = 'SIAE_CoeffMaggiorazioneDipendentiAudio__c';
    private static final String FIELD_MAGG_DIP_VIDEO = 'SIAE_CoeffMaggiorazioneDipendentiVideo__c';

    private static final String ATTR_AREE_EST = 'SIAE-ATTR-AREE-EST';
    private static final String FIELD_COEFF_AREE_EST = 'SIAE_CoeffAreeEsterne__c';

    private static final String TYPE_OF_COVERAGE = 'SIAE_TypeOfCoverage__c';
    private static final String FIELD_COEFF_STAG = 'SIAE_CoeffStagionalita__c';

    private static final String FIELD_COEFF_TV40 = 'SIAE_CoeffMaggiorazioneTV40__c';

    private static final String FIELD_USA_COMP_UNICO = 'SIAE_UsaCompensoUnico__c';

    private static final String ATTR_LUOGO = 'SIAE-ATTR-LUOGO';
    private static final String FIELD_DIVIDI_COMP_VAL = 'SIAE_DividiCompensoValore__c';

    private static final String ATTR_LICENZA_RISTORAZIONE = 'SIAE-ATTR-LIC-RIST';
    private static final String FIELD_LICENZA_RIST = 'SIAE_LicenzaRistorazione__c';

    private static final String ATTR_NUOVA_STRUTTURA = 'SIAE-ATTR-NUOVA-STRU';
    private static final String FIELD_NUOVA_STRU = 'SIAE_NuovaStruttura__c';

    public RevSignaling.TransactionResponse execute(RevSignaling.TransactionRequest request) {

        String contextId = request == null ? null : request.ctxInstanceId;

        ProcessResult result = executeInternal(contextId, new RCAIndustriesContextGateway());

        RevSignaling.TransactionResponse response = new RevSignaling.TransactionResponse();
        response.status = result.success
            ? RevSignaling.TransactionStatus.SUCCESS
            : RevSignaling.TransactionStatus.FAILED;
        response.message = result.message;
        return response;
    }

    @TestVisible
    private static ProcessResult executeInternal(String contextId, RCAContextGateway ctx) {
        try {
            RCASalesTransaction salesTransaction = new RCAContextReader(ctx).read(contextId);

            if (salesTransaction.items.isEmpty()) {
                return new ProcessResult(
                    true,
                    DEBUG_VERSION + ': nessun line item trovato.'
                );
            }

            Set<Id> productIds = new Set<Id>();

            for (RCASalesTransaction.ItemNode item : salesTransaction.items) {
                if (String.isNotBlank(item.productId)) {
                    try {
                        productIds.add((Id) item.productId);
                    } catch (Exception e) {  System.debug(DEBUG_VERSION + ' - Product non valido: ' + item.productId); }
                }
            }

            MdAPricingConfiguration.ConfigurationIndex pricingConfigurations = MdAPricingConfiguration.load(productIds);

            Map<Id, Id> productToSellingModel = loadSellingModelByProduct(productIds);
            Map<Id, String> productToCode = loadProductCodeByProduct(productIds);

            Set<String> productCodes = new Set<String>();
            productCodes.addAll(productToCode.values());

            MdADiffusionResolver.ConfigurationIndex diffusionConfigurations = MdADiffusionResolver.load(CATALOG_CODE, productCodes);

            Map<String, Map<String, String>> qliToAttrValues = new Map<String, Map<String, String>>();

            for (RCASalesTransaction.ItemNode item : salesTransaction.items) {
                for (RCASalesTransaction.AttributeNode attribute : item.attributes) {
                    // Il context espone solo l'Id: riscriviamo il valore testuale
                    // risolto direttamente sul tag AttributeValue del nodo attributo,
                    // cosi' la Pricing Procedure a valle lo trova gia' valorizzato.
                    if (attribute.resolvedFromPicklist && attribute.dataPath != null && attribute.dataPath.size() >= 4) {
                        attribute.attributeToUpdate.put(FIELD_ATTRIBUTE_VALUE, attribute.attributeValue);
                    }

                    if (!qliToAttrValues.containsKey(attribute.parentLineItemId)) {
                        qliToAttrValues.put(attribute.parentLineItemId, new Map<String, String>());
                    }

                    qliToAttrValues.get(attribute.parentLineItemId).put(attribute.attributeCode, attribute.attributeValue);
                }
            }

            for (RCASalesTransaction.ItemNode item : salesTransaction.items) {
                if (item.dataPath == null || item.dataPath.size() < 3) { continue; }

                if ('DELETED'.equals(item.dmlStatus)) {
                    continue;
                }

                String productId = item.productId;

                Date startDate = RCAValueConverter.asDate(item.effectiveFrom);

                SIAE_ConfigurazionePricing__c conf = String.isNotBlank(productId)
                    ? pricingConfigurations.resolve((Id)productId, startDate)
                    : null;

                String currentSellingModel = item.productSellingModel;
                Id resolvedSellingModel = String.isNotBlank(productId) ? productToSellingModel.get((Id)productId) : null;
                String sellingModelValue = String.isNotBlank(currentSellingModel) ? currentSellingModel : resolvedSellingModel;

                String lineItem = item.lineItemId;
                String lineItemPath = item.lineItemPath != null ? item.lineItemPath : lineItem;

                String sourceQliId = (lineItemPath != null && lineItemPath.contains('/')) ? lineItemPath.split('/')[0] : lineItem;

                if (String.isBlank(sourceQliId)) { continue; }

                Map<String, String> attrValues = qliToAttrValues.get(sourceQliId);
                if (attrValues == null) { attrValues = new Map<String, String>(); }

                String productCode = String.isNotBlank(productId) ? productToCode.get((Id)productId) : null;
                Datetime diffusionEffectiveFrom = item.effectiveFrom == null
                    ? item.derivedStartDateTime
                    : RCAValueConverter.asDatetime(item.effectiveFrom);

                MdADiffusionResolver.Result diffusion = MdADiffusionResolver.resolve(
                    diffusionConfigurations,
                    CATALOG_CODE,
                    productCode,
                    diffusionEffectiveFrom,
                    attrValues
                );

                String qtaValue = attrValues.get(ATTR_QTA);
                Decimal mq = SIAE_UTIL_PricingMdA.parseDecimal(qtaValue);
                Decimal coeffMaggiorazioneMQ = SIAE_UTIL_PricingMdA.fattoreMQOltre500(mq, conf);

                String areeEstValue = attrValues.get(ATTR_AREE_EST);
                Decimal coeffAreeEsterne = SIAE_UTIL_PricingMdA.fattoreMaggiorazioneEsterna(areeEstValue, conf);

                String currentTypeOfCoverage = item.typeCoverage;

                String normalizedTypeOfCoverage = SIAE_UTIL_PricingMdA.defaultTypeCoverage(currentTypeOfCoverage, conf);
                Decimal coeffStagionalita = SIAE_UTIL_PricingMdA.coeffStagionalita(normalizedTypeOfCoverage, conf, startDate);

                Decimal coeffTV40 = SIAE_UTIL_PricingMdA.fattoreTV40(conf);

                Integer numDipendenti = SIAE_UTIL_PricingMdA.parseInteger(qtaValue);
                Map<String, Decimal> importiDipendenti = SIAE_UTIL_PricingMdA.importoDipendentiOltre200(numDipendenti, conf);

                // Ente pubblico (COND-SPE=SI): sempre fascia 26-50, nessuna
                // maggiorazione oltre 200 dipendenti.
                String condSpeValue = attrValues.get(SIAE_UTIL_PricingMdA.ATTR_COND_SPE);
                SIAE_UTIL_PricingMdA.azzeraMaggiorazioneDipSeEntePubblico(importiDipendenti, condSpeValue);

                Decimal importoDipRadio = importiDipendenti.get('radio');
                Decimal importoDipAudio = importiDipendenti.get('audio');
                Decimal importoDipVideo = importiDipendenti.get('video');

                String altoparlantiValue = SIAE_UTIL_PricingMdA.altoparlanteValue(conf);
                String monitorValue = SIAE_UTIL_PricingMdA.monitorValue(conf);

                String luogoValue = attrValues.get(ATTR_LUOGO);
                Decimal dividiCompenso = luogoValue != null && luogoValue == 'Solo a terra' ? conf.SIAE_DividiCompensoValore__c : 1;

                String licRis = attrValues.get(ATTR_LICENZA_RISTORAZIONE);
                Decimal licenzaRist = licRis != null && licRis == 'SI'  ? 1 : conf.SIAE_LicenzaRistorazione_Valore__c;

                String nuoStru = attrValues.get(ATTR_NUOVA_STRUTTURA);
                Decimal nuovaStru = nuoStru != null && nuoStru == 'SI' ? conf.SIAE_NuovaStruttura_Valore__c : 1;

                item.attributeToUpdate.put(FIELD_COEFF_MAGG_MQ, String.valueOf(coeffMaggiorazioneMQ));
                item.attributeToUpdate.put(FIELD_COEFF_AREE_EST, String.valueOf(coeffAreeEsterne));
                item.attributeToUpdate.put(FIELD_COEFF_STAG, String.valueOf(coeffStagionalita));
                item.attributeToUpdate.put(TYPE_OF_COVERAGE, normalizedTypeOfCoverage);
                item.attributeToUpdate.put(FIELD_COEFF_TV40, String.valueOf(coeffTV40));
                item.attributeToUpdate.put(FIELD_MAGG_DIP_RADIO, String.valueOf(importoDipRadio));
                item.attributeToUpdate.put(FIELD_MAGG_DIP_AUDIO, String.valueOf(importoDipAudio));
                item.attributeToUpdate.put(FIELD_MAGG_DIP_VIDEO, String.valueOf(importoDipVideo));
                item.attributeToUpdate.put(SIAE_UTIL_PricingMdA.FIELD_DIFF_ALTOPARLANTI, altoparlantiValue);
                item.attributeToUpdate.put(SIAE_UTIL_PricingMdA.FIELD_DIFF_MONITOR, monitorValue);
                item.attributeToUpdate.put(FIELD_USA_COMP_UNICO, conf.SIAE_UsaCompensoUnico__c);
                item.attributeToUpdate.put(FIELD_DIVIDI_COMP_VAL, dividiCompenso);
                item.attributeToUpdate.put(FIELD_LICENZA_RIST, licenzaRist);
                item.attributeToUpdate.put(FIELD_NUOVA_STRU, nuovaStru);
                item.attributeToUpdate.put(FIELD_SELLING_MODEL, sellingModelValue);
                item.attributeToUpdate.put(FIELD_HAS_AUDIO, String.valueOf(diffusion.hasAudio));
                item.attributeToUpdate.put(FIELD_HAS_RADIO, String.valueOf(diffusion.hasRadio));
                item.attributeToUpdate.put(FIELD_HAS_VIDEO, String.valueOf(diffusion.hasVideo));
            }

            List<Map<String, Object>> updates = RCAContextWriter.buildUpdates(salesTransaction);
            if (!updates.isEmpty()) {
                new RCAContextWriter(ctx).write(contextId, salesTransaction);
            }

            return new ProcessResult(
                true,
                DEBUG_VERSION + ': completato con ' + updates.size() + ' update.'
            );

        } catch (Exception e) {
            return new ProcessResult(
                false,
                DEBUG_VERSION + ' Errore: ' + e.getMessage()
            );
        }
    }

    @TestVisible
    private class ProcessResult {
        @TestVisible
        Boolean success;
        @TestVisible
        String message;

        private ProcessResult(Boolean success, String message) {
            this.success = success;
            this.message = message;
        }
    }



    private static Map<Id, Id> loadSellingModelByProduct(Set<Id> productIds) {
        Map<Id, Id> productToSellingModel = new Map<Id, Id>();

        if (productIds == null || productIds.isEmpty()) {
            return productToSellingModel;
        }

        for (ProductSellingModelOption opt : [
            SELECT Product2Id, ProductSellingModelId
              FROM ProductSellingModelOption
              WHERE Product2Id IN :productIds
        ]) {
            if (opt.Product2Id != null
                && opt.ProductSellingModelId != null
                && !productToSellingModel.containsKey(opt.Product2Id)) {
                productToSellingModel.put(opt.Product2Id, opt.ProductSellingModelId);
            }
        }

        return productToSellingModel;
    }

    private static Map<Id, String> loadProductCodeByProduct(Set<Id> productIds) {
        Map<Id, String> productToCode = new Map<Id, String>();

        if (productIds == null || productIds.isEmpty()) {
            return productToCode;
        }

        for (Product2 product : [
            SELECT Id, ProductCode
              FROM Product2
              WHERE Id IN :productIds
        ]) {
            productToCode.put(product.Id, product.ProductCode);
        }

        return productToCode;
    }

}