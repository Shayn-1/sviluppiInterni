/**
 * @description Motore configurabile per recuperare voci incasso e classificazione fiscale materiale
 *              a partire da Product2.ProductCode, AttributeDefinition.Code, CommercialCode
 *              e output del motore Diritti Connessi.
 *
 *              La classificazione fiscale materiale viene letta direttamente
 *              dal campo SIAE_MaterialTaxClassification__c presente su SIAE_VoceIncasso__c.
 *
 *              Input logico DDA:
 *              - Product2.ProductCode
 *              - lista attributi con AttributeDefinitionCode
 *              - deviceTotalPrice
 *
 *              Input logico QA:
 *              - CommercialCode
 *              - quota calcolata esternamente
 *
 *              Input logico DC:
 *              - SIAE_DTO_DirittiConnessiResult
 *              - DispositivoDetail.revenueItem
 *              - DispositivoDetail.importoRiga
 *
 *              Output:
 *              - PaymentItem.itemCode = codice voce incasso
 *              - PaymentItem.amount = deviceTotalPrice dell'attributo, quota o importo calcolato
 *              - PaymentItem.type = DDA / DC / QA
 *              - PaymentItem.materialTaxClassification = classificazione fiscale materiale
              - PaymentItem.instrumentId = id strumento per DDA da SIAE_RegolaVoceIncassoAttributo__c.SIAE_IdInstrument__c
 *
 * @author      Rondinella Francesco
 */
public with sharing class SIAE_UTIL_VoceIncassoEngine {

    private static final Set<String> DEFAULT_FEE_TYPES = new Set<String>{ 'DDA', 'DC' };

    private static final String FEE_TYPE_DDA = 'DDA';
    private static final String FEE_TYPE_DC  = 'DC';
    private static final String FEE_TYPE_QA  = 'QA';
    private static final String FEE_TYPE_SI_DDA = 'SI_DDA';
    private static final String FEE_TYPE_SI_DC  = 'SI_DC';
    private static final String FIELD_TOTAL_DA = 'SIAE_TotalDA__c';
    private static final String FLAT_AUDIO = 'FLAT_AUDIO';
    private static final String FLAT_AUDIO_VIDEO = 'FLAT_AUDIO_VIDEO';

    private class AttributeInput {
        String code;
        Decimal quantity = 0;
        Decimal amount = 0;

        Decimal unitAmount() {
            // DDA: 14
            if (quantity == null || quantity == 0 || amount == null) { return 0;}
            return amount / quantity;
        }

        Decimal consume(Decimal qtyToConsume) {
            // DDA: 13
            if (qtyToConsume == null || qtyToConsume <= 0) { return 0;}

            if (quantity == null || quantity <= 0) { return 0;}

            Decimal realQty = qtyToConsume;

            if (realQty > quantity) { realQty = quantity; }

            Decimal consumedAmount = unitAmount() * realQty;

            quantity -= realQty;
            amount -= consumedAmount;

            if (quantity < 0) { quantity = 0;}

            if (amount < 0) { amount = 0;}

            return consumedAmount;
        }
    }

    private class RuleBundle {
        SIAE_RegolaVoceIncasso__c rule;
        List<SIAE_RegolaVoceIncassoAttributo__c> ruleItems =
            new List<SIAE_RegolaVoceIncassoAttributo__c>();
    }

    private class PaymentItemAggregationEntry {
        String key;
        PricingPaymentItem item;
    }

    public static Map<String, List<PricingPaymentItem>> calculateByLineItems(
        List<RCASalesTransaction.ItemNode> lineItems,
        Map<String, Product2> productById,
        Set<String> feeTypes
    ) {
        return calculateByLineItems(lineItems, productById, feeTypes, null);
    }

    public static Map<String, List<PricingPaymentItem>> calculateByLineItems(
        List<RCASalesTransaction.ItemNode> lineItems,
        Map<String, Product2> productById,
        Set<String> feeTypes,
        MdAPricingConfiguration.ConfigurationIndex pricingConfigurations
    ) {
        // DDA: 1
        Map<String, List<PricingPaymentItem>> resultByLineItemId =
            new Map<String, List<PricingPaymentItem>>();

        if (lineItems == null || lineItems.isEmpty()) { return resultByLineItemId;}

        if (productById == null) { productById = new Map<String, Product2>();}

        if (feeTypes == null || feeTypes.isEmpty()) { feeTypes = DEFAULT_FEE_TYPES;}

        Set<String> productCodes = new Set<String>();

        for (RCASalesTransaction.ItemNode item : lineItems) {
            if (item == null || String.isBlank(item.productId)) { continue; }

            Product2 productRecord = productById.get(item.productId);

            if (productRecord != null && String.isNotBlank(productRecord.ProductCode)) {
                productCodes.add(productRecord.ProductCode);
            }
        }

        if (productCodes.isEmpty()) { return resultByLineItemId; }

        Map<String, Map<String, List<RuleBundle>>> rulesByProductCodeAndFeeType =
            loadRules(productCodes, feeTypes);

        Map<String, Set<String>> additionalFlatAttributeCodesByProductCode =
            pricingConfigurations == null
                ? loadAdditionalFlatAttributeCodesByProductCode(productCodes)
                : new Map<String, Set<String>>();

        for (RCASalesTransaction.ItemNode item : lineItems) {
            if (item == null || String.isBlank(item.lineItemId) || String.isBlank(item.productId)) { continue; }

            Product2 productRecord = productById.get(item.productId);

            if (productRecord == null || String.isBlank(productRecord.ProductCode)) { continue; }

            Map<String, AttributeInput> attributesByCode =
                buildAttributesByCode(item.attributes);

            applyFlatOptionAttributes(item, attributesByCode, feeTypes);

            Map<String, Set<String>> effectiveFlatAttributeCodes = additionalFlatAttributeCodesByProductCode;
            if (pricingConfigurations != null) {
                SIAE_ConfigurazionePricing__c conf = pricingConfigurations.resolve(
                    toId(item.productId),
                    RCAValueConverter.asDate(item.effectiveFrom)
                );
                effectiveFlatAttributeCodes = new Map<String, Set<String>>();
                if (conf != null) {
                    Set<String> codes = splitAttributeCodes(conf.SIAE_AggiungiAFLAT__c);
                    if (!codes.isEmpty()) {
                        effectiveFlatAttributeCodes.put(productRecord.ProductCode, codes);
                    }
                }
            }

            Date effectiveDate = RCAValueConverter.asDate(item.effectiveFrom);

            List<PricingPaymentItem> paymentItems =
                resolveForProductCode(
                    productRecord.ProductCode,
                    attributesByCode,
                    rulesByProductCodeAndFeeType,
                    feeTypes,
                    effectiveFlatAttributeCodes,
                    effectiveDate
                );

            resultByLineItemId.put(item.lineItemId, paymentItems);
        }

        return resultByLineItemId;
    }

    public static List<PricingPaymentItem> calculateByProductCode(
        String productCode,
        List<RCASalesTransaction.AttributeNode> attributes,
        Set<String> feeTypes
    ) {
        return calculateByProductCode(productCode, attributes, feeTypes, null);
    }

    public static List<PricingPaymentItem> calculateByProductCode(
        String productCode,
        List<RCASalesTransaction.AttributeNode> attributes,
        Set<String> feeTypes,
        Date effectiveDate
    ) {
        // DDA, DC: 1 - entrypoint alternativo per calcolo diretto su singolo ProductCode
        if (String.isBlank(productCode)) {
            return new List<PricingPaymentItem>();
        }

        if (feeTypes == null || feeTypes.isEmpty()) {
            feeTypes = DEFAULT_FEE_TYPES;
        }

        Set<String> productCodes = new Set<String>{ productCode };

        Map<String, Map<String, List<RuleBundle>>> rulesByProductCodeAndFeeType =
            loadRules(productCodes, feeTypes);

        Map<String, Set<String>> additionalFlatAttributeCodesByProductCode =
            loadAdditionalFlatAttributeCodesByProductCode(productCodes);

        return resolveForProductCode(
            productCode,
            buildAttributesByCode(attributes),
            rulesByProductCodeAndFeeType,
            feeTypes,
            additionalFlatAttributeCodesByProductCode,
            effectiveDate
        );
    }

    public static String calculateJsonByProductCode(
        String productCode,
        List<RCASalesTransaction.AttributeNode> attributes,
        Set<String> feeTypes
    ) {
        // DDA, DC: 1 - entrypoint alternativo JSON su singolo ProductCode
        return JSON.serialize(calculateByProductCode(productCode, attributes, feeTypes));
    }

    public static Map<String, List<PricingPaymentItem>> addSupplementarySiItemsByLineItem(
        Map<String, List<PricingPaymentItem>> paymentItemsDDAByLineItemId,
        Map<String, List<PricingPaymentItem>> paymentItemsDCByLineItemId
    ) {
        // SI_DDA, SI_DC: 1
        Map<String, List<PricingPaymentItem>> result =
            new Map<String, List<PricingPaymentItem>>();

        Set<String> lineItemIds = new Set<String>();

        if (paymentItemsDDAByLineItemId != null) {
            lineItemIds.addAll(paymentItemsDDAByLineItemId.keySet());
        }

        if (paymentItemsDCByLineItemId != null) {
            lineItemIds.addAll(paymentItemsDCByLineItemId.keySet());
        }

        if (lineItemIds.isEmpty()) {
            return result;
        }

        Boolean needSiDda = false;
        Boolean needSiDc = false;

        for (String lineItemId : lineItemIds) {
            if (hasValidPaymentItems(
                paymentItemsDDAByLineItemId == null ? null
                    : paymentItemsDDAByLineItemId.get(lineItemId)
            )) {
                needSiDda = true;
            }

            if (hasValidPaymentItems(
                paymentItemsDCByLineItemId == null ? null
                    : paymentItemsDCByLineItemId.get(lineItemId)
            )) {
                needSiDc = true;
            }
        }

        if (!needSiDda && !needSiDc) {
            return result;
        }

        Set<String> feeTypesToLoad = new Set<String>();

        if (needSiDda) {
            feeTypesToLoad.add(FEE_TYPE_SI_DDA);
        }

        if (needSiDc) {
            feeTypesToLoad.add(FEE_TYPE_SI_DC);
        }

        Map<String, SIAE_VoceIncasso__c> siRevenueItemByFeeType =
            loadSupplementarySiRevenueItemsByFeeType(feeTypesToLoad);

        for (String lineItemId : lineItemIds) {
            List<PricingPaymentItem> supplementaryItems =
                new List<PricingPaymentItem>();

            Boolean hasDda = hasValidPaymentItems(
                paymentItemsDDAByLineItemId == null ? null
                    : paymentItemsDDAByLineItemId.get(lineItemId)
            );

            Boolean hasDc = hasValidPaymentItems(
                paymentItemsDCByLineItemId == null ? null
                    : paymentItemsDCByLineItemId.get(lineItemId)
            );

            if (hasDda) {
                PricingPaymentItem siDdaItem =
                    toSupplementarySiPaymentItem(
                        siRevenueItemByFeeType.get(FEE_TYPE_SI_DDA),
                        FEE_TYPE_SI_DDA
                    );

                if (siDdaItem != null && String.isNotBlank(siDdaItem.itemCode)) {
                    supplementaryItems.add(siDdaItem);
                }
            }

            if (hasDc) {
                PricingPaymentItem siDcItem =
                    toSupplementarySiPaymentItem(
                        siRevenueItemByFeeType.get(FEE_TYPE_SI_DC),
                        FEE_TYPE_SI_DC
                    );

                if (siDcItem != null && String.isNotBlank(siDcItem.itemCode)) {
                    supplementaryItems.add(siDcItem);
                }
            }

            if (!supplementaryItems.isEmpty()) {
                result.put(lineItemId, supplementaryItems);
            }
        }

        return result;
    }

    public static Map<String, List<PricingPaymentItem>> applyDiscountByLineItems(
        Map<String, List<PricingPaymentItem>> paymentItemsByLineItemId,
        Map<String, Decimal> discountPercentByLineItemId
    ) {
        if (paymentItemsByLineItemId == null) {
            return new Map<String, List<PricingPaymentItem>>();
        }

        if (discountPercentByLineItemId == null || discountPercentByLineItemId.isEmpty()) {
            return paymentItemsByLineItemId;
        }

        Map<String, List<PricingPaymentItem>> result =
            new Map<String, List<PricingPaymentItem>>();

        for (String lineItemId : paymentItemsByLineItemId.keySet()) {
            List<PricingPaymentItem> originalItems =
                paymentItemsByLineItemId.get(lineItemId);

            Decimal discount = discountPercentByLineItemId.get(lineItemId);

            if (discount == null || discount == 0 || originalItems == null || originalItems.isEmpty()) {
                result.put(lineItemId, originalItems);
                continue;
            }

            List<PricingPaymentItem> discountedItems =
                new List<PricingPaymentItem>();

            for (PricingPaymentItem originalItem : originalItems) {
                if (originalItem == null) {
                    continue;
                }

                Decimal amount = parseDecimal(originalItem.amount);

                if (amount == null) {
                    discountedItems.add(originalItem);
                    continue;
                }

                PricingPaymentItem discountedItem =
                    new PricingPaymentItem();

                discountedItem.itemCode = originalItem.itemCode;
                discountedItem.type = originalItem.type;
                discountedItem.materialTaxClassification = originalItem.materialTaxClassification;
                discountedItem.revenueItemType = originalItem.revenueItemType;
                discountedItem.instrumentId = originalItem.instrumentId;
                discountedItem.attributeCode = originalItem.attributeCode;
                discountedItem.amount = formatAmountForJson(amount * (1 - discount));

                discountedItems.add(discountedItem);
            }

            result.put(lineItemId, discountedItems);
        }

        return result;
    }

    private static Boolean hasValidPaymentItems(
        List<PricingPaymentItem> paymentItems
    ) {
        // SI_DDA, SI_DC: 2
        if (paymentItems == null || paymentItems.isEmpty()) {
            return false;
        }

        for (PricingPaymentItem item : paymentItems) {
            if (
                item != null &&
                String.isNotBlank(item.itemCode) &&
                (item.amount != null && String.isNotBlank(String.valueOf(item.amount)))
            ) {
                Decimal amount = parseDecimal(item.amount);

                if (amount != null && amount != 0) {
                    return true;
                }
            }
        }

        return false;
    }

    public static Map<String, List<PricingPaymentItem>> calculateQuotaAssociativaByLineItems(
        List<RCASalesTransaction.ItemNode> lineItems,
        Map<String, Decimal> quotaByLineItemId
    ) {
        // QA: 1
        Map<String, List<PricingPaymentItem>> resultByLineItemId =
            new Map<String, List<PricingPaymentItem>>();

        if (lineItems == null || lineItems.isEmpty()) { return resultByLineItemId; }

        if (quotaByLineItemId == null || quotaByLineItemId.isEmpty()) {
            return resultByLineItemId;
        }

        Set<String> commercialCodes = new Set<String>();

        for (RCASalesTransaction.ItemNode item : lineItems) {
            if (item == null || String.isBlank(item.lineItemId)) {
                continue;
            }

            if (!quotaByLineItemId.containsKey(item.lineItemId)) {
                continue;
            }

            if (String.isBlank(item.commercialCode)) {
                continue;
            }

            commercialCodes.add(normalizeCode(item.commercialCode));
        }

        if (commercialCodes.isEmpty()) {
            return resultByLineItemId;
        }

        Map<String, SIAE_RegolaVoceIncassoAttributo__c> qaRuleItemByCommercialCode =
            loadQaRuleItemsByCommercialCode(commercialCodes);

        if (qaRuleItemByCommercialCode.isEmpty()) {
            return resultByLineItemId;
        }

        for (RCASalesTransaction.ItemNode item : lineItems) {
            if (item == null || String.isBlank(item.lineItemId) || String.isBlank(item.commercialCode)) {
                continue;
            }

            Decimal quota = quotaByLineItemId.get(item.lineItemId);

            if (quota == null || quota == 0) {
                continue;
            }

            String commercialCode = normalizeCode(item.commercialCode);

            SIAE_RegolaVoceIncassoAttributo__c qaRuleItem =
                qaRuleItemByCommercialCode.get(commercialCode);

            if (qaRuleItem == null) {
                continue;
            }

            PricingPaymentItem paymentItem =
                toQuotaAssociativaPaymentItem(qaRuleItem, quota);

            if (paymentItem == null || String.isBlank(paymentItem.itemCode)) {
                continue;
            }

            if (!resultByLineItemId.containsKey(item.lineItemId)) {
                resultByLineItemId.put(
                    item.lineItemId,
                    new List<PricingPaymentItem>()
                );
            }

            resultByLineItemId.get(item.lineItemId).add(paymentItem);
        }

        return resultByLineItemId;
    }

    public static Map<String, List<PricingPaymentItem>> calculateDirittiConnessiByLineItems(
        SIAE_DTO_DirittiConnessiResult dcResult
    ) {
        // DC: 1
        Map<String, List<PricingPaymentItem>> resultByLineItemId =
            new Map<String, List<PricingPaymentItem>>();
    
        if (
            dcResult == null ||
            dcResult.dettagliPerOrderItem == null ||
            dcResult.dettagliPerOrderItem.isEmpty()
        ) {
            return resultByLineItemId;
        }
    
        /*
         * Regola di aggregazione DC aggiornata:
         * - non si aggrega più per sola voce incasso/revenueItemCode;
         * - il PaymentItem resta separato per dispositivo logico;
         * - il dispositivo logico DC viene identificato da tipoDispositivo + revenueItemType;
         * - due righe con stessa voce incasso ma dispositivo logico diverso restano separate;
         * - due righe dello stesso dispositivo logico vengono sommate.
         *
         * Esempio:
         * - stessa voce incasso, tipoDispositivo diverso -> due PaymentItem distinti;
         * - stessa voce incasso, stesso tipoDispositivo -> un PaymentItem aggregato.
         *
         * Il revenueItemType DC ha come fonte primaria
         * SIAE_DTO_DirittiConnessiResult.DispositivoDetail.revenueItemType,
         * valorizzato dal RuleEngine da SIAE_DirittiConnessiRule__c.SIAE_RevenueItemType__c.
         * Il campo su SIAE_VoceIncasso__c resta solo fallback.
         */
        Set<String> revenueItemCodes = new Set<String>();
    
        for (SIAE_DTO_DirittiConnessiResult.LicenzaDetail detail : dcResult.dettagliPerOrderItem) {
            if (
                detail == null ||
                String.isBlank(detail.orderItemId) ||
                detail.dettagliDispositivi == null ||
                detail.dettagliDispositivi.isEmpty()
            ) {
                continue;
            }
    
            for (SIAE_DTO_DirittiConnessiResult.DispositivoDetail dispositivo : detail.dettagliDispositivi) {
                if (
                    dispositivo == null ||
                    String.isBlank(dispositivo.revenueItem) ||
                    dispositivo.importoRiga == null ||
                    dispositivo.importoRiga == 0
                ) {
                    continue;
                }
    
                for (String revenueCode : splitRevenueItems(dispositivo.revenueItem)) {
                    String normalizedRevenueCode = normalizeCode(revenueCode);
    
                    if (String.isNotBlank(normalizedRevenueCode)) {
                        revenueItemCodes.add(normalizedRevenueCode);
                    }
                }
            }
        }
    
        if (revenueItemCodes.isEmpty()) {
            return resultByLineItemId;
        }
    
        /*
         * Una sola query per recuperare la classificazione fiscale materiale
         * delle voci incasso realmente presenti nel risultato DC.
         * SIAE_RevenueItemType__c viene letto solo come fallback se il DTO DC
         * non contiene revenueItemType.
         */
        Map<String, SIAE_VoceIncasso__c> revenueItemByCode =
            loadRevenueItemsByCode(revenueItemCodes);
    
        Map<String, List<PaymentItemAggregationEntry>> entriesByLineItemId =
            new Map<String, List<PaymentItemAggregationEntry>>();
    
        for (SIAE_DTO_DirittiConnessiResult.LicenzaDetail detail : dcResult.dettagliPerOrderItem) {
            if (
                detail == null ||
                String.isBlank(detail.orderItemId) ||
                detail.dettagliDispositivi == null ||
                detail.dettagliDispositivi.isEmpty()
            ) {
                continue;
            }
    
            if (!entriesByLineItemId.containsKey(detail.orderItemId)) {
                entriesByLineItemId.put(
                    detail.orderItemId,
                    new List<PaymentItemAggregationEntry>()
                );
            }
    
            List<PaymentItemAggregationEntry> aggregationEntries =
                entriesByLineItemId.get(detail.orderItemId);
    
            for (SIAE_DTO_DirittiConnessiResult.DispositivoDetail dispositivo : detail.dettagliDispositivi) {
                if (
                    dispositivo == null ||
                    String.isBlank(dispositivo.revenueItem) ||
                    dispositivo.importoRiga == null ||
                    dispositivo.importoRiga == 0
                ) {
                    continue;
                }
    
                List<String> revenueCodes = splitRevenueItems(dispositivo.revenueItem);
    
                if (revenueCodes.isEmpty()) {
                    continue;
                }
    
                /*
                 * Se revenueItem contiene più codici separati da ';',
                 * ripartiamo l'importo in parti uguali.
                 */
                Decimal splitAmount = dispositivo.importoRiga / revenueCodes.size();
    
                for (String revenueCode : revenueCodes) {
                    String normalizedRevenueCode = normalizeCode(revenueCode);
    
                    if (String.isBlank(normalizedRevenueCode)) {
                        continue;
                    }
    
                    PricingPaymentItem paymentItem =
                        toDirittiConnessiPaymentItem(
                            normalizedRevenueCode,
                            splitAmount,
                            dispositivo.revenueItemType,
                            dispositivo.instrumentId,
                            revenueItemByCode
                        );
    
                    if (paymentItem == null || String.isBlank(paymentItem.itemCode)) {
                        continue;
                    }

                    PaymentItemAggregationEntry entry = new PaymentItemAggregationEntry();
                    entry.key = buildDeviceAggregationKey(
                        paymentItem,
                        dispositivo.tipoDispositivo,
                        normalizedRevenueCode
                    );
                    entry.item = paymentItem;

                    aggregationEntries.add(entry);
                }
            }
        }
    
        for (String lineItemId : entriesByLineItemId.keySet()) {
            List<PaymentItemAggregationEntry> aggregationEntries =
                entriesByLineItemId.get(lineItemId);
    
            if (aggregationEntries == null || aggregationEntries.isEmpty()) {
                continue;
            }
    
            resultByLineItemId.put(
                lineItemId,
                aggregateByExplicitKey(aggregationEntries)
            );
        }
    
        return resultByLineItemId;
    }

    private static Map<String, SIAE_VoceIncasso__c> loadSupplementarySiRevenueItemsByFeeType(
        Set<String> feeTypes
    ) {
        // SI_DDA, SI_DC: 3
        Map<String, SIAE_VoceIncasso__c> result =
            new Map<String, SIAE_VoceIncasso__c>();

        if (feeTypes == null || feeTypes.isEmpty()) { return result; }

        List<SIAE_VoceIncasso__c> revenueItems = [
            SELECT Id,
                   Name,
                   SIAE_Code__c,
                   SIAE_FeeType__c,
                   SIAE_MaterialTaxClassification__c,
                   SIAE_RevenueItemType__c,
                   SIAE_Amount__c,
                   SIAE_Active__c
            FROM SIAE_VoceIncasso__c
            WHERE SIAE_FeeType__c IN :feeTypes
            AND SIAE_Active__c = true
            ORDER BY CreatedDate ASC
        ];

        for (SIAE_VoceIncasso__c revenueItem : revenueItems) {
            if (String.isBlank(revenueItem.SIAE_FeeType__c)) {  continue; }

            String feeType = revenueItem.SIAE_FeeType__c.trim();

            if (!result.containsKey(feeType)) {
                result.put(feeType, revenueItem);
            }
        }

        return result;
    }

    private static PricingPaymentItem toSupplementarySiPaymentItem(
        SIAE_VoceIncasso__c revenueItem,
        String feeType
    ) {
        // SI_DDA, SI_DC: 4
        if (revenueItem == null) { return null; }
    
        PricingPaymentItem paymentItem =
            new PricingPaymentItem();
    
        paymentItem.itemCode = revenueItem.SIAE_Code__c;
        paymentItem.amount = formatAmountForJson(parseDecimal(revenueItem.SIAE_Amount__c));
        paymentItem.type = feeType;
        paymentItem.materialTaxClassification =
            revenueItem.SIAE_MaterialTaxClassification__c;
        paymentItem.revenueItemType = String.isNotBlank(revenueItem.SIAE_RevenueItemType__c)
            ? revenueItem.SIAE_RevenueItemType__c
            : feeType;
    
        return paymentItem;
    }

    private static List<String> splitRevenueItems(String rawRevenueItem) {
        // DC: 2
        List<String> result = new List<String>();

        if (String.isBlank(rawRevenueItem)) {
            return result;
        }

        for (String rawCode : rawRevenueItem.split(';')) {
            String code = normalizeCode(rawCode);

            if (String.isNotBlank(code)) {
                result.add(code);
            }
        }

        return result;
    }

    private static Map<String, SIAE_VoceIncasso__c> loadRevenueItemsByCode(
        Set<String> revenueItemCodes
    ) {
        // DC: 3
        Map<String, SIAE_VoceIncasso__c> result =
            new Map<String, SIAE_VoceIncasso__c>();

        if (revenueItemCodes == null || revenueItemCodes.isEmpty()) {
            return result;
        }

        List<SIAE_VoceIncasso__c> revenueItems = [
            SELECT Id,
                   Name,
                   SIAE_Code__c,
                   SIAE_FeeType__c,
                   SIAE_MaterialTaxClassification__c,
                   SIAE_RevenueItemType__c,
                   SIAE_Active__c
            FROM SIAE_VoceIncasso__c
            WHERE SIAE_Code__c IN :revenueItemCodes
            AND SIAE_Active__c = true
        ];

        for (SIAE_VoceIncasso__c revenueItem : revenueItems) {
            if (String.isNotBlank(revenueItem.SIAE_Code__c)) {
                result.put(
                    normalizeCode(revenueItem.SIAE_Code__c),
                    revenueItem
                );
            }
        }

        return result;
    }

    private static PricingPaymentItem toDirittiConnessiPaymentItem(
        String revenueCode,
        Decimal amount,
        String revenueItemType,
        String instrumentId,
        Map<String, SIAE_VoceIncasso__c> revenueItemByCode
    ) {
        // DC: 4
        PricingPaymentItem paymentItem =
            new PricingPaymentItem();

        paymentItem.itemCode = normalizeCode(revenueCode);
        paymentItem.amount = formatAmountForJson(amount);
        paymentItem.type = FEE_TYPE_DC;
        paymentItem.instrumentId = instrumentId;

        SIAE_VoceIncasso__c revenueItem =
            revenueItemByCode == null
                ? null
                : revenueItemByCode.get(normalizeCode(revenueCode));

        paymentItem.materialTaxClassification =
            revenueItem == null
                ? null
                : revenueItem.SIAE_MaterialTaxClassification__c;

        paymentItem.revenueItemType = String.isNotBlank(revenueItemType)
            ? revenueItemType
            : (
                revenueItem == null
                    ? null
                    : revenueItem.SIAE_RevenueItemType__c
            );

        return paymentItem;
    }

    private static Map<String, Map<String, List<RuleBundle>>> loadRules(
        Set<String> productCodes,
        Set<String> feeTypes
    ) {
        // DDA: 2
        Map<String, Map<String, List<RuleBundle>>> result =
            new Map<String, Map<String, List<RuleBundle>>>();

        if (productCodes == null || productCodes.isEmpty() || feeTypes == null || feeTypes.isEmpty()) {  return result; }

        List<SIAE_RegolaVoceIncasso__c> rules = [
            SELECT Id,
                   Name,
                   SIAE_ExternalId__c,
                   SIAE_Product2__c,
                   SIAE_Product2__r.ProductCode,
                   SIAE_FeeType__c,
                   SIAE_RuleType__c,
                   SIAE_Priority__c,
                   SIAE_Active__c,
                   SIAE_DataInizioValidita__c,
                   SIAE_DataFineValidita__c
            FROM SIAE_RegolaVoceIncasso__c
            WHERE SIAE_Product2__r.ProductCode IN :productCodes
            AND SIAE_FeeType__c IN :feeTypes
            AND SIAE_Active__c = true
            ORDER BY SIAE_Product2__r.ProductCode,
                     SIAE_FeeType__c,
                     SIAE_Priority__c ASC,
                     CreatedDate ASC
        ];

        if (rules.isEmpty()) {
            return result;
        }

        Set<Id> ruleIds = new Set<Id>();
        Map<Id, RuleBundle> bundleByRuleId = new Map<Id, RuleBundle>();

        for (SIAE_RegolaVoceIncasso__c rule : rules) {
            if (rule.SIAE_Product2__r == null || String.isBlank(rule.SIAE_Product2__r.ProductCode)) { continue;}

            String productCode = rule.SIAE_Product2__r.ProductCode;
            String feeType = rule.SIAE_FeeType__c;

            ruleIds.add(rule.Id);

            RuleBundle bundle = new RuleBundle();
            bundle.rule = rule;
            bundleByRuleId.put(rule.Id, bundle);

            if (!result.containsKey(productCode)) {
                result.put(productCode, new Map<String, List<RuleBundle>>());
            }

            Map<String, List<RuleBundle>> byFeeType = result.get(productCode);

            if (!byFeeType.containsKey(feeType)) {
                byFeeType.put(feeType, new List<RuleBundle>());
            }

            byFeeType.get(feeType).add(bundle);
        }

        List<SIAE_RegolaVoceIncassoAttributo__c> ruleItems = [
            SELECT Id,
                   Name,
                   SIAE_ExternalId__c,
                   SIAE_RevenueItemRule__c,

                   SIAE_RevenueItem__c,
                   SIAE_RevenueItem__r.SIAE_Code__c,
                   SIAE_RevenueItem__r.SIAE_FeeType__c,
                   SIAE_RevenueItem__r.SIAE_MaterialTaxClassification__c,
            	   SIAE_RevenueItem__r.SIAE_RevenueItemType__c,

                   SIAE_AttributeDefinition__c,
                   SIAE_AttributeDefinition__r.Code,
                   SIAE_AttributeCode__c,
                   SIAE_IdInstrument__c,

                   SIAE_MinQuantity__c,
                   SIAE_MaxQuantity__c,
                   SIAE_Required__c,
                   SIAE_PercentageAllocation__c,
                   SIAE_Active__c
            FROM SIAE_RegolaVoceIncassoAttributo__c
            WHERE SIAE_RevenueItemRule__c IN :ruleIds
            AND SIAE_Active__c = true
            ORDER BY CreatedDate ASC
        ];

        for (SIAE_RegolaVoceIncassoAttributo__c item : ruleItems) {
            RuleBundle bundle = bundleByRuleId.get(item.SIAE_RevenueItemRule__c);

            if (bundle != null) {
                bundle.ruleItems.add(item);
            }
        }

        return result;
    }

    private static Map<String, Set<String>> loadAdditionalFlatAttributeCodesByProductCode(
        Set<String> productCodes
    ) {
        Map<String, Set<String>> result = new Map<String, Set<String>>();

        if (productCodes == null || productCodes.isEmpty()) {
            return result;
        }

        List<SIAE_ConfigurazionePricing__c> configurations = [
            SELECT Id,
                   SIAE_Product2__r.ProductCode,
                   SIAE_AggiungiAFLAT__c
            FROM SIAE_ConfigurazionePricing__c
            WHERE SIAE_Attivo__c = true
            AND SIAE_Product2__r.ProductCode IN :productCodes
        ];

        for (SIAE_ConfigurazionePricing__c conf : configurations) {
            if (
                conf.SIAE_Product2__r == null ||
                String.isBlank(conf.SIAE_Product2__r.ProductCode)
            ) {
                continue;
            }

            String productCode = conf.SIAE_Product2__r.ProductCode;
            Set<String> attributeCodes = splitAttributeCodes(conf.SIAE_AggiungiAFLAT__c);

            if (attributeCodes.isEmpty()) {
                continue;
            }

            if (!result.containsKey(productCode)) {
                result.put(productCode, new Set<String>());
            }

            result.get(productCode).addAll(attributeCodes);
        }

        return result;
    }

    private static Map<String, SIAE_RegolaVoceIncassoAttributo__c> loadQaRuleItemsByCommercialCode(
        Set<String> commercialCodes
    ) {
        // QA: 2
        Map<String, SIAE_RegolaVoceIncassoAttributo__c> result =
            new Map<String, SIAE_RegolaVoceIncassoAttributo__c>();

        if (commercialCodes == null || commercialCodes.isEmpty()) {
            return result;
        }

        List<SIAE_RegolaVoceIncassoAttributo__c> qaRuleItems = [
            SELECT Id,
                   Name,
                   SIAE_ExternalId__c,
                   SIAE_Active__c,
                   SIAE_CommercialCode__c,

                   SIAE_RevenueItemRule__c,
                   SIAE_RevenueItemRule__r.SIAE_FeeType__c,
                   SIAE_RevenueItemRule__r.SIAE_RuleType__c,
                   SIAE_RevenueItemRule__r.SIAE_Priority__c,
                   SIAE_RevenueItemRule__r.SIAE_Active__c,

                   SIAE_RevenueItem__c,
                   SIAE_RevenueItem__r.SIAE_Code__c,
                   SIAE_RevenueItem__r.SIAE_FeeType__c,
                   SIAE_RevenueItem__r.SIAE_MaterialTaxClassification__c,
                   SIAE_RevenueItem__r.SIAE_Active__c,
            	   SIAE_RevenueItem__r.SIAE_RevenueItemType__c
            FROM SIAE_RegolaVoceIncassoAttributo__c
            WHERE SIAE_Active__c = true
            AND SIAE_CommercialCode__c IN :commercialCodes
            AND SIAE_RevenueItemRule__r.SIAE_Active__c = true
            AND SIAE_RevenueItemRule__r.SIAE_FeeType__c = :FEE_TYPE_QA
            AND SIAE_RevenueItemRule__r.SIAE_RuleType__c = :FEE_TYPE_QA
            AND SIAE_RevenueItem__r.SIAE_Active__c = true
            ORDER BY SIAE_RevenueItemRule__r.SIAE_Priority__c ASC,
                     CreatedDate ASC
        ];

        for (SIAE_RegolaVoceIncassoAttributo__c qaRuleItem : qaRuleItems) {
            if (String.isBlank(qaRuleItem.SIAE_CommercialCode__c)) {
                continue;
            }

            String commercialCode = normalizeCode(qaRuleItem.SIAE_CommercialCode__c);

            if (!result.containsKey(commercialCode)) {
                result.put(commercialCode, qaRuleItem);
            }
        }

        return result;
    }

    private static List<PricingPaymentItem> resolveForProductCode(
        String productCode,
        Map<String, AttributeInput> attributesByCode,
        Map<String, Map<String, List<RuleBundle>>> rulesByProductCodeAndFeeType,
        Set<String> feeTypes,
        Map<String, Set<String>> additionalFlatAttributeCodesByProductCode,
        Date effectiveDate
    ) {
        // DDA: 4
        List<PricingPaymentItem> output =
            new List<PricingPaymentItem>();

        if (String.isBlank(productCode)) { return output; }

        Map<String, List<RuleBundle>> rulesByFeeType =
            rulesByProductCodeAndFeeType.get(productCode);

        if (rulesByFeeType == null || rulesByFeeType.isEmpty()) {
            return output;
        }

        for (String feeType : feeTypes) {
            List<RuleBundle> bundles = rulesByFeeType.get(feeType);

            if (bundles == null || bundles.isEmpty()) { continue; }

            Map<String, AttributeInput> remainingAttributes =
                cloneAttributes(attributesByCode);

            if (FEE_TYPE_DDA.equals(feeType)) {
                remainingAttributes = filterDdaAttributesForFlatOption(
                    remainingAttributes,
                    additionalFlatAttributeCodesByProductCode == null
                        ? null
                        : additionalFlatAttributeCodesByProductCode.get(productCode)
                );
            }

            for (RuleBundle bundle : bundles) {
                if (!isRuleValidOn(bundle.rule, effectiveDate)) {
                    continue;
                }

                String ruleType = normalizeRuleType(bundle.rule.SIAE_RuleType__c);

                List<PricingPaymentItem> resolved =
                    evaluateRule(bundle, remainingAttributes);

                if (!resolved.isEmpty()) {
                    output.addAll(resolved);

                    if (shouldStopAfterResolvedRule(feeType, ruleType, remainingAttributes)) { break; }
                }
            }
        }

        return output;
    }


    @TestVisible
    private static Boolean isRuleValidOn(
        SIAE_RegolaVoceIncasso__c rule,
        Date effectiveDate
    ) {
        if (rule == null) {
            return false;
        }

        // Backward compatibility for entrypoints that do not provide an effective date.
        // The line-item pricing path always provides QLI.EffectiveFrom.
        if (effectiveDate == null) {
            return true;
        }

        Date validFrom = rule.SIAE_DataInizioValidita__c == null
            ? null
            : rule.SIAE_DataInizioValidita__c.dateGMT();
        Date validTo = rule.SIAE_DataFineValidita__c == null
            ? null
            : rule.SIAE_DataFineValidita__c.dateGMT();

        return (validFrom == null || effectiveDate >= validFrom)
            && (validTo == null || effectiveDate <= validTo);
    }

    private static List<PricingPaymentItem> evaluateRule(
        RuleBundle bundle,
        Map<String, AttributeInput> attributesByCode
    ) {
        // DDA: 6
        if (bundle == null || bundle.rule == null) { return new List<PricingPaymentItem>(); }

        String ruleType = normalizeRuleType(bundle.rule.SIAE_RuleType__c);

        if ('BY_ATTRIBUTE'.equals(ruleType) || 'FLAT_OPTION'.equals(ruleType)) {
            return evaluateByAttributeOrFlat(bundle, attributesByCode);
        }

        if ('COMBINATION'.equals(ruleType)) { return evaluateCombination(bundle, attributesByCode); }

        if ('FIXED_PRICE'.equals(ruleType)) { return evaluateFixedPrice(bundle, attributesByCode); }

        if ('SPLIT'.equals(ruleType)) { return evaluateSplit(bundle, attributesByCode); }

        if ('FALLBACK'.equals(ruleType)) { return evaluateFixedPrice(bundle, attributesByCode); }

        return new List<PricingPaymentItem>();
    }

    private static List<PricingPaymentItem> evaluateByAttributeOrFlat(
        RuleBundle bundle,
        Map<String, AttributeInput> attributesByCode
    ) {
        // DDA: 7
        List<PricingPaymentItem> result =
            new List<PricingPaymentItem>();

        if (bundle.ruleItems == null || bundle.ruleItems.isEmpty()) { return result; }

        for (SIAE_RegolaVoceIncassoAttributo__c ruleItem : bundle.ruleItems) {
            String ruleItemCode = getRuleItemCode(ruleItem);

            if (String.isBlank(ruleItemCode)) { continue; }

            AttributeInput inputAttr = attributesByCode.get(ruleItemCode);

            if (inputAttr == null || inputAttr.quantity == null || inputAttr.quantity <= 0) { continue; }

            if (!quantityMatches(ruleItem, inputAttr.quantity)) {  continue;  }

            Decimal consumedAmount = inputAttr.consume(inputAttr.quantity);

            result.add(toPaymentItem(ruleItem, bundle.rule.SIAE_FeeType__c, consumedAmount));
        }

        return result;
    }

    private static List<PricingPaymentItem> evaluateCombination(
        RuleBundle bundle,
        Map<String, AttributeInput> attributesByCode
    ) {
        // DDA: 7
        List<PricingPaymentItem> result =
            new List<PricingPaymentItem>();

        if (bundle.ruleItems == null || bundle.ruleItems.isEmpty()) { return result; }

        Boolean allRequiredMatched = true;

        for (SIAE_RegolaVoceIncassoAttributo__c ruleItem : bundle.ruleItems) {
            String ruleItemCode = getRuleItemCode(ruleItem);
            Boolean required = ruleItem.SIAE_Required__c == true;

            if (!required) {
                continue;
            }

            if (String.isBlank(ruleItemCode)) {
                allRequiredMatched = false;
                break;
            }

            AttributeInput inputAttr = attributesByCode.get(ruleItemCode);

            if (inputAttr == null) {
                allRequiredMatched = false;
                break;
            }

            Decimal requiredQty = getRequiredQuantity(ruleItem);

            if (inputAttr.quantity == null || inputAttr.quantity < requiredQty) {
                allRequiredMatched = false;
                break;
            }

            if (!quantityMatches(ruleItem, inputAttr.quantity)) {
                allRequiredMatched = false;
                break;
            }
        }

        if (!allRequiredMatched) {
            return result;
        }

        /*
         * Non aggreghiamo più per SIAE_RevenueItem__c.
         * In caso di stessa voce incasso su dispositivi/logiche diverse,
         * ogni ruleItem genera il proprio PaymentItem.
         * L'eventuale aggregazione del medesimo itemCode dispositivo avviene già
         * a monte tramite buildAttributesByCode, che somma per AttributeDefinitionCode.
         */
        for (SIAE_RegolaVoceIncassoAttributo__c ruleItem : bundle.ruleItems) {
            String ruleItemCode = getRuleItemCode(ruleItem);

            if (String.isBlank(ruleItemCode)) {  continue; }

            AttributeInput inputAttr = attributesByCode.get(ruleItemCode);

            if (inputAttr == null || ruleItem.SIAE_RevenueItem__c == null) {
                continue;
            }

            Decimal qtyToConsume = getRequiredQuantity(ruleItem);
            Decimal consumedAmount = inputAttr.consume(qtyToConsume);

            result.add(
                toPaymentItem(
                    ruleItem,
                    bundle.rule.SIAE_FeeType__c,
                    consumedAmount
                )
            );
        }

        return result;
    }

    private static List<PricingPaymentItem> evaluateFixedPrice(
        RuleBundle bundle,
        Map<String, AttributeInput> attributesByCode
    ) {
        // DDA: 7
        List<PricingPaymentItem> result =
            new List<PricingPaymentItem>();

        Decimal totalDevicePrice = calculateTotalDevicePrice(attributesByCode);

        if (bundle.ruleItems == null || bundle.ruleItems.isEmpty()) { return result; }

        for (SIAE_RegolaVoceIncassoAttributo__c ruleItem : bundle.ruleItems) {
            String ruleItemCode = getRuleItemCode(ruleItem);
            Decimal amount = totalDevicePrice;

            if (String.isNotBlank(ruleItemCode) && attributesByCode.containsKey(ruleItemCode)) {
                amount = attributesByCode.get(ruleItemCode).amount;
            }

            result.add(toPaymentItem(ruleItem, bundle.rule.SIAE_FeeType__c, amount));
        }

        return result;
    }

    private static List<PricingPaymentItem> evaluateSplit(
        RuleBundle bundle,
        Map<String, AttributeInput> attributesByCode
    ) {
        // DDA: 7
        List<PricingPaymentItem> result =
            new List<PricingPaymentItem>();

        Decimal totalDevicePrice = calculateTotalDevicePrice(attributesByCode);

        if (bundle.ruleItems == null || bundle.ruleItems.isEmpty()) {
            return result;
        }

        for (SIAE_RegolaVoceIncassoAttributo__c ruleItem : bundle.ruleItems) {
            Decimal percentage = ruleItem.SIAE_PercentageAllocation__c == null
                ? 0
                : ruleItem.SIAE_PercentageAllocation__c;

            Decimal amount = percentage == 0
                ? 0
                : totalDevicePrice * percentage / 100;

            result.add(toPaymentItem(ruleItem, bundle.rule.SIAE_FeeType__c, amount));
        }

        return result;
    }

    private static void applyFlatOptionAttributes(
        RCASalesTransaction.ItemNode item,
        Map<String, AttributeInput> attributesByCode,
        Set<String> feeTypes
    ) {
        // DDA FLAT: se la flat è selezionata a livello di line item,
        // la trasformiamo in attributo logico FLAT_AUDIO/FLAT_AUDIO_VIDEO.
        if (item == null || attributesByCode == null || !shouldApplyDdaFlatOption(feeTypes)) {
            return;
        }

        String flatCode = resolveFlatOptionCode(item.typeOfFlatRate);

        if (String.isBlank(flatCode)) {
            return;
        }

        AttributeInput flatInput = attributesByCode.get(flatCode);

        if (flatInput == null) {
            flatInput = new AttributeInput();
            flatInput.code = flatCode;
            attributesByCode.put(flatCode, flatInput);
        }

        flatInput.quantity = 1;

        Decimal flatAmount = resolveFlatOptionAmount(item, flatCode, flatInput.amount);
        flatInput.amount = flatAmount == null ? 0 : flatAmount;
    }

    private static Map<String, AttributeInput> filterDdaAttributesForFlatOption(
        Map<String, AttributeInput> attributesByCode,
        Set<String> additionalFlatAttributeCodes
    ) {
        // DDA FLAT: se è presente una flat, non devono essere valutati tutti i dispositivi.
        // Restano valutabili solo la flat e gli apparecchi configurati in SIAE_AggiungiAFLAT__c.
        if (attributesByCode == null || attributesByCode.isEmpty()) {
            return attributesByCode;
        }

        String flatCode = resolveFlatOptionCodeFromAttributes(attributesByCode);

        if (String.isBlank(flatCode)) {
            return attributesByCode;
        }

        Map<String, AttributeInput> result = new Map<String, AttributeInput>();
        AttributeInput flatInput = attributesByCode.get(flatCode);

        if (flatInput == null) {
            flatInput = new AttributeInput();
            flatInput.code = flatCode;
            flatInput.quantity = 1;
            flatInput.amount = 0;
        }

        result.put(flatCode, flatInput);

        Set<String> normalizedAdditionalCodes = normalizeCodeSet(additionalFlatAttributeCodes);

        for (String additionalCode : normalizedAdditionalCodes) {
            if (String.isBlank(additionalCode) || flatCode.equals(additionalCode)) {
                continue;
            }

            if (attributesByCode.containsKey(additionalCode)) {
                result.put(additionalCode, attributesByCode.get(additionalCode));
            }
        }

        return result;
    }

    private static Boolean shouldStopAfterResolvedRule(
        String feeType,
        String ruleType,
        Map<String, AttributeInput> remainingAttributes
    ) {
        if (
            FEE_TYPE_DDA.equals(feeType) &&
            'FLAT_OPTION'.equals(ruleType) &&
            hasAdditionalFlatAttributes(remainingAttributes)
        ) {
            return false;
        }

        return
            'FLAT_OPTION'.equals(ruleType) ||
            'FIXED_PRICE'.equals(ruleType) ||
            'SPLIT'.equals(ruleType);
    }

    private static Boolean hasAdditionalFlatAttributes(
        Map<String, AttributeInput> attributesByCode
    ) {
        if (attributesByCode == null || attributesByCode.isEmpty()) {
            return false;
        }

        String flatCode = resolveFlatOptionCodeFromAttributes(attributesByCode);

        if (String.isBlank(flatCode)) {
            return false;
        }

        for (String code : attributesByCode.keySet()) {
            if (String.isNotBlank(code) && !flatCode.equals(code)) {
                return true;
            }
        }

        return false;
    }

    private static Set<String> splitAttributeCodes(String rawCodes) {
        Set<String> result = new Set<String>();

        if (String.isBlank(rawCodes)) {
            return result;
        }

        for (String rawCode : rawCodes.split(';')) {
            String code = normalizeCode(rawCode);

            if (String.isNotBlank(code)) {
                result.add(code);
            }
        }

        return result;
    }

    private static Set<String> normalizeCodeSet(Set<String> source) {
        Set<String> result = new Set<String>();

        if (source == null || source.isEmpty()) {
            return result;
        }

        for (String rawCode : source) {
            String code = normalizeCode(rawCode);

            if (String.isNotBlank(code)) {
                result.add(code);
            }
        }

        return result;
    }

    private static Boolean shouldApplyDdaFlatOption(Set<String> feeTypes) {
        if (feeTypes == null || feeTypes.isEmpty()) {
            return true;
        }

        return feeTypes.contains(FEE_TYPE_DDA);
    }

    private static String resolveFlatOptionCode(String typeOfFlatRate) {
        if (String.isBlank(typeOfFlatRate)) {
            return null;
        }

        String normalizedType = typeOfFlatRate.trim().toUpperCase().replace('-', '_').replace(' ', '_');

        if (normalizedType == FLAT_AUDIO) {
            return FLAT_AUDIO;
        }

        if (normalizedType == FLAT_AUDIO_VIDEO) {
            return FLAT_AUDIO_VIDEO;
        }

        return null;
    }

    private static String resolveFlatOptionCodeFromAttributes(
        Map<String, AttributeInput> attributesByCode
    ) {
        if (attributesByCode == null || attributesByCode.isEmpty()) {
            return null;
        }

        if (attributesByCode.containsKey(FLAT_AUDIO_VIDEO)) {
            return FLAT_AUDIO_VIDEO;
        }

        if (attributesByCode.containsKey(FLAT_AUDIO)) {
            return FLAT_AUDIO;
        }

        return null;
    }

    private static Decimal resolveFlatOptionAmount(
        RCASalesTransaction.ItemNode item,
        String flatCode,
        Decimal currentAmount
    ) {
        Decimal calculatedFlatAmount = calculateFlatOptionBaseAmount(item, flatCode);

        if (calculatedFlatAmount != null && calculatedFlatAmount > 0) {
            return calculatedFlatAmount;
        }

        if (currentAmount != null && currentAmount > 0) {
            return currentAmount;
        }

        return 0;
    }

    private static Decimal calculateFlatOptionBaseAmount(
        RCASalesTransaction.ItemNode item,
        String flatCode
    ) {
        if (item == null || String.isBlank(flatCode)) {
            return 0;
        }

        Decimal baseAmount = 0;

        if (FLAT_AUDIO.equals(flatCode)) {
            baseAmount = item.flatAudioAmount == null ? 0 : item.flatAudioAmount;
        }

        if (FLAT_AUDIO_VIDEO.equals(flatCode)) {
            baseAmount = item.flatVideoAmount == null ? 0 : item.flatVideoAmount;
        }

        return
            baseAmount *
            coeffOrOne(item.coeffMaggiorazioneMQ) *
            coeffOrOne(item.coeffAreeEsterne) *
            coeffOrOne(item.periodicityCoefficient);
    }

    private static Decimal coeffOrOne(Decimal coeff) {
        return coeff == null ? 1 : coeff;
    }

    private static Map<String, AttributeInput> buildAttributesByCode(
        List<RCASalesTransaction.AttributeNode> attributes
    ) {
        // DDA: 3
        Map<String, AttributeInput> result = new Map<String, AttributeInput>();

        if (attributes == null || attributes.isEmpty()) {
            return result;
        }

        for (RCASalesTransaction.AttributeNode attr : attributes) {
            if (attr == null || String.isBlank(attr.attributeCode)) { continue; }

            String code = normalizeCode(attr.attributeCode);

            if (String.isBlank(code)) {  continue; }

            if (!result.containsKey(code)) {
                AttributeInput input = new AttributeInput();
                input.code = code;
                result.put(code, input);
            }

            AttributeInput existing = result.get(code);

            Decimal quantity = parseDecimal(attr.attributeValue);

            if (quantity == null) {
                quantity = 1;
            }

            Decimal amount = parseDecimal(attr.deviceTotalPrice);

            if (amount == null) {
                amount = 0;
            }

            existing.quantity += quantity;
            existing.amount += amount;
        }

        return result;
    }

    private static Map<String, AttributeInput> cloneAttributes(
        Map<String, AttributeInput> source
    ) {
        // DDA: 5
        Map<String, AttributeInput> cloned = new Map<String, AttributeInput>();

        if (source == null) { return cloned; }

        for (String code : source.keySet()) {
            AttributeInput original = source.get(code);

            if (original == null) { continue; }

            AttributeInput copy = new AttributeInput();
            copy.code = original.code;
            copy.quantity = original.quantity;
            copy.amount = original.amount;

            cloned.put(code, copy);
        }

        return cloned;
    }

    private static Decimal getRequiredQuantity(
        SIAE_RegolaVoceIncassoAttributo__c ruleItem
    ) {
        // DDA: 8
        if (ruleItem == null || ruleItem.SIAE_MinQuantity__c == null) { return 1; }

        return ruleItem.SIAE_MinQuantity__c;
    }

    private static PricingPaymentItem toPaymentItem(
        SIAE_RegolaVoceIncassoAttributo__c ruleItem,
        String feeType,
        Decimal amount
    ) {
        // DDA: 9
        PricingPaymentItem paymentItem =
            new PricingPaymentItem();

        paymentItem.itemCode =
            ruleItem.SIAE_RevenueItem__r == null ? null
                : ruleItem.SIAE_RevenueItem__r.SIAE_Code__c;

        paymentItem.amount = formatAmountForJson(amount);
        paymentItem.type = feeType;
        paymentItem.materialTaxClassification = getMaterialTaxClassification(ruleItem);
        paymentItem.revenueItemType = ruleItem.SIAE_RevenueItem__r.SIAE_RevenueItemType__c;
        paymentItem.instrumentId = ruleItem.SIAE_IdInstrument__c;
        paymentItem.attributeCode = getRuleItemCode(ruleItem);

        return paymentItem;
    }

    private static PricingPaymentItem toQuotaAssociativaPaymentItem(
        SIAE_RegolaVoceIncassoAttributo__c qaRuleItem,
        Decimal quota
    ) {
        // QA: 3
        if (qaRuleItem == null || qaRuleItem.SIAE_RevenueItem__r == null) {
            return null;
        }

        PricingPaymentItem paymentItem =
            new PricingPaymentItem();

        paymentItem.itemCode = qaRuleItem.SIAE_RevenueItem__r.SIAE_Code__c;
        paymentItem.amount = formatAmountForJson(quota);
        paymentItem.type = FEE_TYPE_QA;
        paymentItem.materialTaxClassification = qaRuleItem.SIAE_RevenueItem__r.SIAE_MaterialTaxClassification__c;
        paymentItem.revenueItemType = qaRuleItem.SIAE_RevenueItem__r.SIAE_RevenueItemType__c;

        return paymentItem;
    }

    private static String getMaterialTaxClassification(
        SIAE_RegolaVoceIncassoAttributo__c ruleItem
    ) {
        // DDA: 10
        if (ruleItem == null || ruleItem.SIAE_RevenueItem__r == null) {  return null; }

        return ruleItem.SIAE_RevenueItem__r.SIAE_MaterialTaxClassification__c;
    }

    private static String getRuleItemCode(SIAE_RegolaVoceIncassoAttributo__c ruleItem) {
        // DDA: 8
        if (ruleItem == null) {  return null; }

        if (String.isNotBlank(ruleItem.SIAE_AttributeCode__c)) {
            return normalizeCode(ruleItem.SIAE_AttributeCode__c);
        }

        if ( ruleItem.SIAE_AttributeDefinition__r != null && String.isNotBlank(ruleItem.SIAE_AttributeDefinition__r.Code)) {  return normalizeCode(ruleItem.SIAE_AttributeDefinition__r.Code); }

        return null;
    }

    private static Boolean quantityMatches(
        SIAE_RegolaVoceIncassoAttributo__c ruleItem,
        Decimal quantity
    ) {
        // DDA: 8
        if (ruleItem == null) { return false;
        }

        if (quantity == null) { quantity = 0; }

        if (ruleItem.SIAE_MinQuantity__c != null && quantity < ruleItem.SIAE_MinQuantity__c) { return false; }

        if (ruleItem.SIAE_MaxQuantity__c != null && quantity > ruleItem.SIAE_MaxQuantity__c) { return false; }

        return true;
    }

    private static Decimal calculateTotalDevicePrice(Map<String, AttributeInput> attributesByCode) {
        // DDA: 8
        Decimal total = 0;

        if (attributesByCode == null || attributesByCode.isEmpty()) { return total; }

        for (AttributeInput input : attributesByCode.values()) {
            if (input != null && input.amount != null) { total += input.amount; }
        }

        return total;
    }


    private static String buildDeviceAggregationKey(
        PricingPaymentItem item,
        String deviceItemCode,
        String revenueCode
    ) {
        if (item == null) {
            return null;
        }

        return String.valueOf(item.type) + '|' +
            normalizeCode(deviceItemCode) + '|' +
            normalizeCode(revenueCode) + '|' +
            normalizeCode(item.revenueItemType) + '|' +
            normalizeCode(item.materialTaxClassification);
    }

    private static List<PricingPaymentItem> aggregateByExplicitKey(
        List<PaymentItemAggregationEntry> input
    ) {
        List<PricingPaymentItem> result =
            new List<PricingPaymentItem>();

        if (input == null || input.isEmpty()) { return result; }

        Map<String, PricingPaymentItem> itemByKey =
            new Map<String, PricingPaymentItem>();

        Map<String, Decimal> amountByKey = new Map<String, Decimal>();
        List<String> orderedKeys = new List<String>();

        for (PaymentItemAggregationEntry entry : input) {
            if (entry == null || entry.item == null || String.isBlank(entry.item.itemCode)) {
                continue;
            }

            String key = String.isBlank(entry.key)
                ? String.valueOf(entry.item.type) + '|' +
                    String.valueOf(entry.item.itemCode) + '|' +
                    String.valueOf(entry.item.revenueItemType) + '|' +
                    String.valueOf(entry.item.instrumentId) + '|' +
                    String.valueOf(entry.item.materialTaxClassification)
                : entry.key;

            Decimal amount = parseDecimal(entry.item.amount);

            if (amount == null) { amount = 0; }

            if (!itemByKey.containsKey(key)) {
                PricingPaymentItem aggregated =
                    new PricingPaymentItem();

                aggregated.itemCode = entry.item.itemCode;
                aggregated.type = entry.item.type;
                aggregated.materialTaxClassification = entry.item.materialTaxClassification;
                aggregated.revenueItemType = entry.item.revenueItemType;
                aggregated.instrumentId = entry.item.instrumentId;

                itemByKey.put(key, aggregated);
                amountByKey.put(key, 0);
                orderedKeys.add(key);
            } else {
                if (
                    String.isBlank(itemByKey.get(key).revenueItemType) &&
                    String.isNotBlank(entry.item.revenueItemType)
                ) {
                    itemByKey.get(key).revenueItemType = entry.item.revenueItemType;
                }

                if (
                    String.isBlank(itemByKey.get(key).instrumentId) &&
                    String.isNotBlank(entry.item.instrumentId)
                ) {
                    itemByKey.get(key).instrumentId = entry.item.instrumentId;
                }
            }

            amountByKey.put(key, amountByKey.get(key) + amount);
        }

        for (String key : orderedKeys) {
            PricingPaymentItem aggregated = itemByKey.get(key);
            Decimal totalAmount = amountByKey.get(key);

            aggregated.amount = formatAmountForJson(totalAmount);

            result.add(aggregated);
        }

        return result;
    }

    public static List<PricingPaymentItem> deduplicate(
        List<PricingPaymentItem> input
    ) {
        // DDA: 11, DC: 5, SI_DDA: 5, SI_DC: 5
        List<PricingPaymentItem> result =
            new List<PricingPaymentItem>();

        if (input == null || input.isEmpty()) { return result; }

        Map<String, PricingPaymentItem> itemByKey =
            new Map<String, PricingPaymentItem>();

        Map<String, Decimal> amountByKey = new Map<String, Decimal>();
        List<String> orderedKeys = new List<String>();

        for (PricingPaymentItem item : input) {
            if (item == null || String.isBlank(item.itemCode)) { continue; }

            /*
             * Chiave di aggregazione intenzionalmente più granulare della sola voce incasso:
             * itemCode da solo non basta, perché la stessa voce può essere usata
             * da itemCode/logiche dispositivo diverse.
             */
            String key =
                String.valueOf(item.type) + '|' +
                String.valueOf(item.itemCode) + '|' +
                String.valueOf(item.revenueItemType) + '|' +
                String.valueOf(item.instrumentId) + '|' +
                String.valueOf(item.materialTaxClassification);

            Decimal amount = parseDecimal(item.amount);

            if (amount == null) { amount = 0; }

            if (!itemByKey.containsKey(key)) {
                PricingPaymentItem aggregated =
                    new PricingPaymentItem();

                aggregated.itemCode = item.itemCode;
                aggregated.type = item.type;
                aggregated.materialTaxClassification = item.materialTaxClassification;
                aggregated.revenueItemType = item.revenueItemType;
                aggregated.instrumentId = item.instrumentId;

                itemByKey.put(key, aggregated);
                amountByKey.put(key, 0);
                orderedKeys.add(key);
            } else {
                if (
                    String.isBlank(itemByKey.get(key).revenueItemType) &&
                    String.isNotBlank(item.revenueItemType)
                ) {
                    itemByKey.get(key).revenueItemType = item.revenueItemType;
                }

                if (
                    String.isBlank(itemByKey.get(key).instrumentId) &&
                    String.isNotBlank(item.instrumentId)
                ) {
                    itemByKey.get(key).instrumentId = item.instrumentId;
                }
            }

            amountByKey.put(key, amountByKey.get(key) + amount);
        }

        for (String key : orderedKeys) {
            PricingPaymentItem aggregated = itemByKey.get(key);
            Decimal totalAmount = amountByKey.get(key);

            aggregated.amount = formatAmountForJson(totalAmount);

            result.add(aggregated);
        }

        return result;
    }

    private static String formatAmountForJson(Decimal amount) {
        // DDA: 10, QA: 4, DC: 5, SI_DDA: 5, SI_DC: 5
        if (amount == null) { return null; }

        return String.valueOf(
            amount.setScale(2, RoundingMode.HALF_UP)
        );
    }

    private static Decimal parseDecimal(Object value) {
        // DDA: 3, SI_DDA: 2, SI_DC: 2
        if (value == null) {
            return null;
        }

        try {
            if (value instanceof Decimal) { return (Decimal) value; }

            String raw = String.valueOf(value);

            if (String.isBlank(raw)) { return null; }

            raw = raw.trim();

            if (raw.contains(',') && raw.contains('.')) { raw = raw.replace('.', '').replace(',', '.'); } 
            else if (raw.contains(',')) { raw = raw.replace(',', '.'); }

            return Decimal.valueOf(raw);
        } catch (Exception e) {
            return null;
        }
    }

    private static String normalizeCode(String code) {
        // DDA: 3, QA: 2, DC: 2
        if (String.isBlank(code)) { return null; }

        return code.trim();
    }

    private static String normalizeRuleType(String ruleType) {
        // DDA: 6
        if (String.isBlank(ruleType)) { return null; }

        String value = ruleType.trim().toUpperCase();

        if (value.contains('FLAT')) { return 'FLAT_OPTION'; }

        if (value.contains('FIXED') || value.contains('PREZZO') || value.contains('UNICA')) { return 'FIXED_PRICE'; }

        if (value.contains('COMBINATION') || value.contains('COMBINAZIONE')) { return 'COMBINATION'; }

        if (value.contains('SPLIT') || value.contains('RIPARTIZIONE')) { return 'SPLIT'; }

        if (value.contains('ATTRIBUTE') || value.contains('ATTRIBUTO')) {
            return 'BY_ATTRIBUTE';
        }

        if (value.contains('FALLBACK')) { return 'FALLBACK'; }

        if (value == FEE_TYPE_QA || value.contains('QUOTA')) { return FEE_TYPE_QA; }

        return value.replace(' ', '_');
    }

    private static Id toId(String value) {
        if (String.isBlank(value)) { return null; }
        try { return (Id)value; } catch (Exception e) { return null; }
    }
}