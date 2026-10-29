@IsTest
private class SIAE_UTIL_VoceIncassoEngine_T {

    private static Integer counter = 0;

    private static String nextSuffix() {
        counter++;
        return String.valueOf(DateTime.now().getTime()) + '_' + String.valueOf(counter);
    }

    private static String activePicklistValue(Schema.SObjectField fieldToken, List<String> preferredValues) {
        Schema.DescribeFieldResult dfr = fieldToken.getDescribe();

        for (String preferred : preferredValues) {
            if (String.isBlank(preferred)) {
                continue;
            }

            for (Schema.PicklistEntry entry : dfr.getPicklistValues()) {
                if (
                    entry != null &&
                    entry.isActive() &&
                    String.isNotBlank(entry.getValue()) &&
                    entry.getValue() == preferred
                ) {
                    return entry.getValue();
                }
            }
        }

        for (String preferred : preferredValues) {
            if (String.isBlank(preferred)) {
                continue;
            }

            String upperPreferred = preferred.toUpperCase();

            for (Schema.PicklistEntry entry : dfr.getPicklistValues()) {
                if (
                    entry != null &&
                    entry.isActive() &&
                    String.isNotBlank(entry.getValue()) &&
                    entry.getValue().toUpperCase().contains(upperPreferred)
                ) {
                    return entry.getValue();
                }
            }
        }

        for (Schema.PicklistEntry entry : dfr.getPicklistValues()) {
            if (entry != null && entry.isActive() && String.isNotBlank(entry.getValue())) {
                return entry.getValue();
            }
        }

        return null;
    }

    private static Boolean isActivePicklistValue(Schema.SObjectField fieldToken, String value) {
        if (String.isBlank(value)) {
            return false;
        }

        for (Schema.PicklistEntry entry : fieldToken.getDescribe().getPicklistValues()) {
            if (
                entry != null &&
                entry.isActive() &&
                entry.getValue() == value
            ) {
                return true;
            }
        }

        return false;
    }

    private static Product2 makeProduct(String code) {
        Product2 p = new Product2(
            Name = 'Test Product ' + code,
            ProductCode = code,
            IsActive = true
        );
        insert p;
        return p;
    }

    private static SIAE_VoceIncasso__c makeRevenueItem(String feeType, String code, String amount) {
        String materialTaxClassification = activePicklistValue(
            SIAE_VoceIncasso__c.SIAE_MaterialTaxClassification__c,
            new List<String>{ 'E' }
        );

        SIAE_VoceIncasso__c revenueItem = new SIAE_VoceIncasso__c(
            Name = feeType + ' - ' + code + ' - TEST',
            SIAE_Active__c = true,
            SIAE_Code__c = code,
            SIAE_ExternalId__c = 'TEST-REV-' + feeType + '-' + code + '-' + nextSuffix(),
            SIAE_FeeType__c = feeType,
            SIAE_MaterialTaxClassification__c = materialTaxClassification
        );

        if (amount != null) {
            revenueItem.SIAE_Amount__c = amount;
        }

        insert revenueItem;
        return revenueItem;
    }

    private static SIAE_RegolaVoceIncasso__c makeRule(
        Product2 productRecord,
        String feeType,
        String ruleType,
        Integer priority
    ) {
        SIAE_RegolaVoceIncasso__c rule = new SIAE_RegolaVoceIncasso__c(
            Name = feeType + ' - ' + ruleType + ' - TEST',
            SIAE_Active__c = true,
            SIAE_ExternalId__c = 'TEST-RULE-' + feeType + '-' + ruleType.replace(' ', '-') + '-' + nextSuffix(),
            SIAE_Priority__c = priority,
            SIAE_Product2__c = productRecord == null ? null : productRecord.Id,
            SIAE_FeeType__c = feeType,
            SIAE_RuleType__c = ruleType
        );
        insert rule;
        return rule;
    }

    private static SIAE_RegolaVoceIncassoAttributo__c makeRuleItem(
        SIAE_RegolaVoceIncasso__c rule,
        SIAE_VoceIncasso__c revenueItem,
        String attributeCode,
        Boolean requiredFlag,
        Decimal minQty,
        Decimal maxQty,
        Decimal percentage,
        String commercialCode
    ) {
        SIAE_RegolaVoceIncassoAttributo__c ruleItem =
            new SIAE_RegolaVoceIncassoAttributo__c(
                Name = 'TEST-RITEM-' + nextSuffix(),
                SIAE_Active__c = true,
                SIAE_ExternalId__c = 'TEST-RITEM-' + nextSuffix(),
                SIAE_RevenueItemRule__c = rule == null ? null : rule.Id,
                SIAE_RevenueItem__c = revenueItem == null ? null : revenueItem.Id,
                SIAE_AttributeCode__c = attributeCode,
                SIAE_Required__c = requiredFlag
            );

        if (minQty != null) {
            ruleItem.SIAE_MinQuantity__c = minQty;
        }

        if (maxQty != null) {
            ruleItem.SIAE_MaxQuantity__c = maxQty;
        }

        if (percentage != null) {
            ruleItem.SIAE_PercentageAllocation__c = percentage;
        }

        if (String.isNotBlank(commercialCode)) {
            ruleItem.SIAE_CommercialCode__c = commercialCode;
        }

        insert ruleItem;
        return ruleItem;
    }


    private static SIAE_RegolaVoceIncassoAttributo__c makeRuleItem(
        SIAE_RegolaVoceIncasso__c rule,
        SIAE_VoceIncasso__c revenueItem,
        String attributeCode,
        Boolean requiredFlag,
        Decimal minQty,
        Decimal maxQty,
        Decimal percentage,
        String commercialCode,
        String instrumentId
    ) {
        SIAE_RegolaVoceIncassoAttributo__c ruleItem = makeRuleItem(
            rule,
            revenueItem,
            attributeCode,
            requiredFlag,
            minQty,
            maxQty,
            percentage,
            commercialCode
        );

        if (String.isNotBlank(instrumentId)) {
            ruleItem.SIAE_IdInstrument__c = instrumentId;
            update ruleItem;
        }

        return ruleItem;
    }

    private static void makeFlatPricingConfiguration(
        Product2 productRecord,
        String additionalFlatAttributes
    ) {
        SIAE_ConfigurazionePricing__c conf = new SIAE_ConfigurazionePricing__c(
            SIAE_Product2__c = productRecord == null ? null : productRecord.Id,
            SIAE_Attivo__c = true,
            SIAE_AggiungiAFLAT__c = additionalFlatAttributes
        );

        insert conf;
    }

    private static PricingPaymentItem findPaymentItem(
        List<PricingPaymentItem> items,
        String type,
        String itemCode
    ) {
        if (items == null) {
            return null;
        }

        for (PricingPaymentItem item : items) {
            if (
                item != null &&
                item.type == type &&
                item.itemCode == itemCode
            ) {
                return item;
            }
        }

        return null;
    }

    private static RCASalesTransaction.AttributeNode makeAttr(
        String attributeCode,
        String attributeValue,
        Object deviceTotalPrice
    ) {
        RCASalesTransaction.AttributeNode attr =
            new RCASalesTransaction.AttributeNode();

        attr.attributeCode = attributeCode;
        attr.attributeValue = attributeValue;
        attr.deviceTotalPrice = deviceTotalPrice;

        return attr;
    }

    private static RCASalesTransaction.ItemNode makeLine(
        Product2 productRecord,
        String lineItemId,
        List<RCASalesTransaction.AttributeNode> attributes
    ) {
        RCASalesTransaction.ItemNode item =
            new RCASalesTransaction.ItemNode();

        item.productId = productRecord == null ? null : productRecord.Id;
        item.lineItemId = lineItemId;
        item.attributes = attributes == null
            ? new List<RCASalesTransaction.AttributeNode>()
            : attributes;

        return item;
    }

    private static PricingPaymentItem paymentItem(
        String type,
        String code,
        String amount
    ) {
        PricingPaymentItem item =
            new PricingPaymentItem();

        item.type = type;
        item.itemCode = code;
        item.amount = amount;
        item.materialTaxClassification = 'E';

        return item;
    }

    private static List<String> valuesByKeyword(Schema.SObjectField fieldToken, List<String> keywords) {
        List<String> values = new List<String>();

        for (String keyword : keywords) {
            String value = activePicklistValue(fieldToken, new List<String>{ keyword });

            if (String.isNotBlank(value) && !values.contains(value)) {
                values.add(value);
            }
        }

        return values;
    }

    @IsTest
    static void testCalculateByLineItems_ByAttributeDda() {
        String byAttribute = activePicklistValue(
            SIAE_RegolaVoceIncasso__c.SIAE_RuleType__c,
            new List<String>{ 'By Attribute', 'ATTRIBUTE', 'ATTRIBUTO' }
        );

        Product2 productRecord = makeProduct('TEST-PROD-BYATTR-' + nextSuffix());
        SIAE_VoceIncasso__c revenueItem = makeRevenueItem('DDA', 'T2216', null);
        SIAE_RegolaVoceIncasso__c rule = makeRule(productRecord, 'DDA', byAttribute, 1);
        makeRuleItem(rule, revenueItem, 'TEST-ATTR-RADIO', true, 1, null, null, null);

        RCASalesTransaction.ItemNode line = makeLine(
            productRecord,
            'LINE-BYATTR',
            new List<RCASalesTransaction.AttributeNode>{
                makeAttr('TEST-ATTR-RADIO', '2', '20')
            }
        );

        Test.startTest();
        Map<String, List<PricingPaymentItem>> result =
            SIAE_UTIL_VoceIncassoEngine.calculateByLineItems(
                new List<RCASalesTransaction.ItemNode>{ line },
                new Map<String, Product2>{ String.valueOf(productRecord.Id) => productRecord },
                new Set<String>{ 'DDA' }
            );
        Test.stopTest();

    }

    @IsTest
    static void testCalculateByProductCode_FixedPrice() {
        String fixedPrice = activePicklistValue(
            SIAE_RegolaVoceIncasso__c.SIAE_RuleType__c,
            new List<String>{ 'Fixed Price', 'FIXED', 'PREZZO', 'UNICA' }
        );

        Product2 productRecord = makeProduct('TEST-PROD-FIXED-' + nextSuffix());
        SIAE_VoceIncasso__c revenueItem = makeRevenueItem('DDA', 'T2272', null);
        SIAE_RegolaVoceIncasso__c rule = makeRule(productRecord, 'DDA', fixedPrice, 1);
        makeRuleItem(rule, revenueItem, null, false, null, null, null, null);

        List<RCASalesTransaction.AttributeNode> attrs =
            new List<RCASalesTransaction.AttributeNode>{
                makeAttr('TEST-ATTR-A', '1', '30'),
                makeAttr('TEST-ATTR-B', '1', '70')
            };

        Test.startTest();
        List<PricingPaymentItem> result =
            SIAE_UTIL_VoceIncassoEngine.calculateByProductCode(
                productRecord.ProductCode,
                attrs,
                new Set<String>{ 'DDA' }
            );
        Test.stopTest();

    }

    @IsTest
    static void testCalculateByProductCode_Split() {
        String split = activePicklistValue(
            SIAE_RegolaVoceIncasso__c.SIAE_RuleType__c,
            new List<String>{ 'Split', 'RIPARTIZIONE' }
        );

        Product2 productRecord = makeProduct('TEST-PROD-SPLIT-' + nextSuffix());
        SIAE_VoceIncasso__c revenueItem1 = makeRevenueItem('DC', 'T0787', null);
        SIAE_VoceIncasso__c revenueItem2 = makeRevenueItem('DC', 'T0788', null);
        SIAE_RegolaVoceIncasso__c rule = makeRule(productRecord, 'DC', split, 1);

        makeRuleItem(rule, revenueItem1, null, false, null, null, 50, null);
        makeRuleItem(rule, revenueItem2, null, false, null, null, 50, null);

        List<RCASalesTransaction.AttributeNode> attrs =
            new List<RCASalesTransaction.AttributeNode>{
                makeAttr('TEST-ATTR-A', '1', '100')
            };

        Test.startTest();
        List<PricingPaymentItem> result =
            SIAE_UTIL_VoceIncassoEngine.calculateByProductCode(
                productRecord.ProductCode,
                attrs,
                new Set<String>{ 'DC' }
            );
        Test.stopTest();

    }

    @IsTest
    static void testCalculateByProductCode_Combination() {
        String combination = activePicklistValue(
            SIAE_RegolaVoceIncasso__c.SIAE_RuleType__c,
            new List<String>{ 'Combination', 'COMBINAZIONE' }
        );

        Product2 productRecord = makeProduct('TEST-PROD-COMB-' + nextSuffix());
        SIAE_VoceIncasso__c revenueItem = makeRevenueItem('DC', 'T0794', null);
        SIAE_RegolaVoceIncasso__c rule = makeRule(productRecord, 'DC', combination, 1);

        makeRuleItem(rule, revenueItem, 'TEST-ATTR-RADIO', true, 1, null, null, null);
        makeRuleItem(rule, revenueItem, 'TEST-ATTR-TV', true, 1, null, null, null);

        List<RCASalesTransaction.AttributeNode> attrs =
            new List<RCASalesTransaction.AttributeNode>{
                makeAttr('TEST-ATTR-RADIO', '1', '40'),
                makeAttr('TEST-ATTR-TV', '1', '60')
            };

        Test.startTest();
        List<PricingPaymentItem> result =
            SIAE_UTIL_VoceIncassoEngine.calculateByProductCode(
                productRecord.ProductCode,
                attrs,
                new Set<String>{ 'DC' }
            );
        Test.stopTest();
    }

    @IsTest
    static void testCalculateByProductCode_FlatOptionIfAvailable() {
        String flatOption = activePicklistValue(
            SIAE_RegolaVoceIncasso__c.SIAE_RuleType__c,
            new List<String>{ 'Flat Option', 'FLAT' }
        );

        if (String.isBlank(flatOption)) {
            return;
        }

        Product2 productRecord = makeProduct('TEST-PROD-FLAT-' + nextSuffix());
        SIAE_VoceIncasso__c revenueItem = makeRevenueItem('DC', 'T0782', null);
        SIAE_RegolaVoceIncasso__c rule = makeRule(productRecord, 'DC', flatOption, 1);
        makeRuleItem(rule, revenueItem, 'FLAT_AUDIO', true, null, null, null, null);

        List<RCASalesTransaction.AttributeNode> attrs =
            new List<RCASalesTransaction.AttributeNode>{
                makeAttr('FLAT_AUDIO', '1', '80')
            };

        Test.startTest();
        List<PricingPaymentItem> result =
            SIAE_UTIL_VoceIncassoEngine.calculateByProductCode(
                productRecord.ProductCode,
                attrs,
                new Set<String>{ 'DC' }
            );
        Test.stopTest();

    }

    @IsTest
    static void testCalculateQuotaAssociativaByLineItemsIfQaPicklistsAvailable() {
        if (
            !isActivePicklistValue(SIAE_RegolaVoceIncasso__c.SIAE_FeeType__c, 'QA') ||
            !isActivePicklistValue(SIAE_RegolaVoceIncasso__c.SIAE_RuleType__c, 'QA') ||
            !isActivePicklistValue(SIAE_VoceIncasso__c.SIAE_FeeType__c, 'QA')
        ) {
            return;
        }

        String commercialCode = activePicklistValue(
            SIAE_RegolaVoceIncassoAttributo__c.SIAE_CommercialCode__c,
            new List<String>{ 'QA' }
        );

        if (String.isBlank(commercialCode)) {
            return;
        }

        Product2 productRecord = makeProduct('TEST-PROD-QA-' + nextSuffix());
        SIAE_VoceIncasso__c revenueItem = makeRevenueItem('QA', 'TQA01', null);
        SIAE_RegolaVoceIncasso__c rule = makeRule(productRecord, 'QA', 'QA', 1);
        makeRuleItem(rule, revenueItem, null, false, null, null, null, commercialCode);

        RCASalesTransaction.ItemNode line =
            makeLine(productRecord, 'LINE-QA', null);
        line.commercialCode = commercialCode;

        Test.startTest();
        Map<String, List<PricingPaymentItem>> result =
            SIAE_UTIL_VoceIncassoEngine.calculateQuotaAssociativaByLineItems(
                new List<RCASalesTransaction.ItemNode>{ line },
                new Map<String, Decimal>{ 'LINE-QA' => 12.5 }
            );
        Test.stopTest();

    }

    @IsTest
    static void testCalculateDirittiConnessiByLineItems() {
        makeRevenueItem('DC', 'T0787', null);
        makeRevenueItem('DC', 'T0788', null);

        SIAE_DTO_DirittiConnessiResult dcResult =
            new SIAE_DTO_DirittiConnessiResult();

        dcResult.dettagliPerOrderItem =
            new List<SIAE_DTO_DirittiConnessiResult.LicenzaDetail>();

        SIAE_DTO_DirittiConnessiResult.LicenzaDetail detail =
            new SIAE_DTO_DirittiConnessiResult.LicenzaDetail();

        detail.orderItemId = 'LINE-DC';
        detail.dettagliDispositivi =
            new List<SIAE_DTO_DirittiConnessiResult.DispositivoDetail>();

        SIAE_DTO_DirittiConnessiResult.DispositivoDetail dispositivo =
            new SIAE_DTO_DirittiConnessiResult.DispositivoDetail();

        dispositivo.revenueItem = 'T0787;T0788';
        dispositivo.revenueItemType = 'LC';
        dispositivo.instrumentId = '6';
        dispositivo.importoRiga = 100;

        detail.dettagliDispositivi.add(dispositivo);
        dcResult.dettagliPerOrderItem.add(detail);

        Test.startTest();
        Map<String, List<PricingPaymentItem>> result =
            SIAE_UTIL_VoceIncassoEngine.calculateDirittiConnessiByLineItems(dcResult);
        Test.stopTest();

        System.assertEquals(true, result.containsKey('LINE-DC'), 'La riga DC deve essere presente');
        System.assertEquals(2, result.get('LINE-DC').size(), 'Il revenueItem separato da ; deve produrre due PaymentItem');

        PricingPaymentItem item0787 = findPaymentItem(
            result.get('LINE-DC'),
            'DC',
            'T0787'
        );

        PricingPaymentItem item0788 = findPaymentItem(
            result.get('LINE-DC'),
            'DC',
            'T0788'
        );

        System.assertNotEquals(null, item0787, 'PaymentItem T0787 non trovato');
        System.assertNotEquals(null, item0788, 'PaymentItem T0788 non trovato');
        System.assertEquals('6', item0787.instrumentId, 'InstrumentId DC non propagato su T0787');
        System.assertEquals('6', item0788.instrumentId, 'InstrumentId DC non propagato su T0788');
        System.assertEquals('LC', item0787.revenueItemType, 'RevenueItemType DC non propagato');
        System.assertEquals('50.00', item0787.amount, 'Importo T0787 non ripartito correttamente');
        System.assertEquals('50.00', item0788.amount, 'Importo T0788 non ripartito correttamente');
    }

    @IsTest
    static void testCalculateByLineItems_DdaFlatWithAdditionalAFlatDevices() {
        String flatOption = activePicklistValue(
            SIAE_RegolaVoceIncasso__c.SIAE_RuleType__c,
            new List<String>{ 'Flat Option', 'FLAT' }
        );

        String byAttribute = activePicklistValue(
            SIAE_RegolaVoceIncasso__c.SIAE_RuleType__c,
            new List<String>{ 'By Attribute', 'ATTRIBUTE', 'ATTRIBUTO' }
        );

        if (String.isBlank(flatOption) || String.isBlank(byAttribute)) {
            return;
        }

        Product2 productRecord = makeProduct('TEST-PROD-DDA-FLAT-AFLAT-' + nextSuffix());

        makeFlatPricingConfiguration(productRecord, 'TEST-ATTR-JUKEBOX');

        SIAE_VoceIncasso__c flatRevenueItem = makeRevenueItem('DDA', 'T2282', null);
        SIAE_VoceIncasso__c jukeboxRevenueItem = makeRevenueItem('DDA', 'T2229', null);
        SIAE_VoceIncasso__c radioRevenueItem = makeRevenueItem('DDA', 'T2231', null);
        SIAE_VoceIncasso__c audioRevenueItem = makeRevenueItem('DDA', 'T2272', null);

        SIAE_RegolaVoceIncasso__c flatRule = makeRule(productRecord, 'DDA', flatOption, 1);
        makeRuleItem(flatRule, flatRevenueItem, 'FLAT_AUDIO', true, 1, null, null, null);

        SIAE_RegolaVoceIncasso__c byAttrRule = makeRule(productRecord, 'DDA', byAttribute, 10);
        makeRuleItem(byAttrRule, jukeboxRevenueItem, 'TEST-ATTR-JUKEBOX', true, 1, null, null, null, '6');
        makeRuleItem(byAttrRule, radioRevenueItem, 'TEST-ATTR-RADIO', true, 1, null, null, null, '3');
        makeRuleItem(byAttrRule, audioRevenueItem, 'TEST-ATTR-AUDIO', true, 1, null, null, null, '13');

        RCASalesTransaction.ItemNode line = makeLine(
            productRecord,
            'LINE-DDA-FLAT-AFLAT',
            new List<RCASalesTransaction.AttributeNode>{
                makeAttr('TEST-ATTR-RADIO', '2', '207.42'),
                makeAttr('TEST-ATTR-AUDIO', '1', '234.79'),
                makeAttr('TEST-ATTR-JUKEBOX', '1', '66.21')
            }
        );

        line.typeOfFlatRate = 'FLAT_AUDIO';
        line.flatAudioAmount = 384.60;
        line.coeffMaggiorazioneMQ = 1.10;
        line.coeffAreeEsterne = 1;
        line.periodicityCoefficient = 1;

        Test.startTest();
        Map<String, List<PricingPaymentItem>> result =
            SIAE_UTIL_VoceIncassoEngine.calculateByLineItems(
                new List<RCASalesTransaction.ItemNode>{ line },
                new Map<String, Product2>{ String.valueOf(productRecord.Id) => productRecord },
                new Set<String>{ 'DDA' }
            );
        Test.stopTest();

        System.assertEquals(true, result.containsKey('LINE-DDA-FLAT-AFLAT'), 'La riga DDA flat deve essere presente');

        List<PricingPaymentItem> items = result.get('LINE-DDA-FLAT-AFLAT');

        PricingPaymentItem flatItem = findPaymentItem(items, 'DDA', 'T2282');
        PricingPaymentItem jukeboxItem = findPaymentItem(items, 'DDA', 'T2229');
        PricingPaymentItem radioItem = findPaymentItem(items, 'DDA', 'T2231');
        PricingPaymentItem audioItem = findPaymentItem(items, 'DDA', 'T2272');

        System.assertNotEquals(null, flatItem, 'La voce flat DDA deve essere generata');
        System.assertNotEquals(null, jukeboxItem, 'L’apparecchio A-FLAT configurato deve essere generato');
        System.assertEquals(null, radioItem, 'Con flat selezionata non deve valutare Radio come DDA dispositivo');
        System.assertEquals(null, audioItem, 'Con flat selezionata non deve valutare Audio come DDA dispositivo');

        System.assertEquals('423.06', flatItem.amount, 'Importo flat DDA errato');
        System.assertEquals('66.21', jukeboxItem.amount, 'Importo apparecchio A-FLAT errato');
        System.assertEquals('6', jukeboxItem.instrumentId, 'InstrumentId apparecchio A-FLAT non valorizzato');
    }

    @IsTest
    static void testCalculateByLineItems_DdaFlatWithoutAdditionalDevicesDoesNotEvaluateDevices() {
        String flatOption = activePicklistValue(
            SIAE_RegolaVoceIncasso__c.SIAE_RuleType__c,
            new List<String>{ 'Flat Option', 'FLAT' }
        );

        String byAttribute = activePicklistValue(
            SIAE_RegolaVoceIncasso__c.SIAE_RuleType__c,
            new List<String>{ 'By Attribute', 'ATTRIBUTE', 'ATTRIBUTO' }
        );

        if (String.isBlank(flatOption) || String.isBlank(byAttribute)) {
            return;
        }

        Product2 productRecord = makeProduct('TEST-PROD-DDA-FLAT-ONLY-' + nextSuffix());

        makeFlatPricingConfiguration(productRecord, null);

        SIAE_VoceIncasso__c flatRevenueItem = makeRevenueItem('DDA', 'T2282', null);
        SIAE_VoceIncasso__c jukeboxRevenueItem = makeRevenueItem('DDA', 'T2229', null);
        SIAE_VoceIncasso__c radioRevenueItem = makeRevenueItem('DDA', 'T2231', null);

        SIAE_RegolaVoceIncasso__c flatRule = makeRule(productRecord, 'DDA', flatOption, 1);
        makeRuleItem(flatRule, flatRevenueItem, 'FLAT_AUDIO', true, 1, null, null, null);

        SIAE_RegolaVoceIncasso__c byAttrRule = makeRule(productRecord, 'DDA', byAttribute, 10);
        makeRuleItem(byAttrRule, jukeboxRevenueItem, 'TEST-ATTR-JUKEBOX', true, 1, null, null, null, '6');
        makeRuleItem(byAttrRule, radioRevenueItem, 'TEST-ATTR-RADIO', true, 1, null, null, null, '3');

        RCASalesTransaction.ItemNode line = makeLine(
            productRecord,
            'LINE-DDA-FLAT-ONLY',
            new List<RCASalesTransaction.AttributeNode>{
                makeAttr('TEST-ATTR-RADIO', '2', '207.42'),
                makeAttr('TEST-ATTR-JUKEBOX', '1', '66.21')
            }
        );

        line.typeOfFlatRate = 'FLAT_AUDIO';
        line.flatAudioAmount = 384.60;
        line.coeffMaggiorazioneMQ = 1;
        line.coeffAreeEsterne = 1;
        line.periodicityCoefficient = 1;

        Test.startTest();
        Map<String, List<PricingPaymentItem>> result =
            SIAE_UTIL_VoceIncassoEngine.calculateByLineItems(
                new List<RCASalesTransaction.ItemNode>{ line },
                new Map<String, Product2>{ String.valueOf(productRecord.Id) => productRecord },
                new Set<String>{ 'DDA' }
            );
        Test.stopTest();

        List<PricingPaymentItem> items = result.get('LINE-DDA-FLAT-ONLY');

        System.assertNotEquals(null, findPaymentItem(items, 'DDA', 'T2282'), 'La voce flat DDA deve essere generata');
        System.assertEquals(null, findPaymentItem(items, 'DDA', 'T2229'), 'Jukebox non configurato in A-FLAT non deve essere generato');
        System.assertEquals(null, findPaymentItem(items, 'DDA', 'T2231'), 'Radio non deve essere generata con flat selezionata');
        System.assertEquals('384.60', findPaymentItem(items, 'DDA', 'T2282').amount, 'Importo flat puro errato');
    }

    @IsTest
    static void testAddSupplementarySiItemsByLineItem() {
        if (
            !isActivePicklistValue(SIAE_VoceIncasso__c.SIAE_FeeType__c, 'SI_DDA') ||
            !isActivePicklistValue(SIAE_VoceIncasso__c.SIAE_FeeType__c, 'SI_DC')
        ) {
            return;
        }

        makeRevenueItem('SI_DDA', 'SD3760', '3');
        makeRevenueItem('SI_DC', 'SD3760', '1');

        Map<String, List<PricingPaymentItem>> ddaByLine =
            new Map<String, List<PricingPaymentItem>>{
                'LINE-SI-DDA' => new List<PricingPaymentItem>{
                    paymentItem('DDA', 'T2216', '50.00')
                },
                'LINE-SI-BOTH' => new List<PricingPaymentItem>{
                    paymentItem('DDA', 'T2216', '70.00')
                },
                'LINE-INVALID' => new List<PricingPaymentItem>{
                    paymentItem('DDA', 'T0000', '0.00')
                }
            };

        Map<String, List<PricingPaymentItem>> dcByLine =
            new Map<String, List<PricingPaymentItem>>{
                'LINE-SI-DC' => new List<PricingPaymentItem>{
                    paymentItem('DC', 'T0787', '10.00')
                },
                'LINE-SI-BOTH' => new List<PricingPaymentItem>{
                    paymentItem('DC', 'T0788', '30.00')
                }
            };

        Test.startTest();
        Map<String, List<PricingPaymentItem>> result =
            SIAE_UTIL_VoceIncassoEngine.addSupplementarySiItemsByLineItem(
                ddaByLine,
                dcByLine
            );
        Test.stopTest();

    }

    @IsTest
    static void testEmptyInputs() {
        Test.startTest();
        System.assertEquals(
            0,
            SIAE_UTIL_VoceIncassoEngine.calculateByLineItems(null, null, null).size()
        );

        System.assertEquals(
            0,
            SIAE_UTIL_VoceIncassoEngine.calculateByProductCode(null, null, null).size()
        );

        System.assertEquals(
            0,
            SIAE_UTIL_VoceIncassoEngine.calculateQuotaAssociativaByLineItems(null, null).size()
        );

        System.assertEquals(
            0,
            SIAE_UTIL_VoceIncassoEngine.calculateDirittiConnessiByLineItems(null).size()
        );

        System.assertEquals(
            0,
            SIAE_UTIL_VoceIncassoEngine.addSupplementarySiItemsByLineItem(null, null).size()
        );
        Test.stopTest();
    }

    @IsTest
    static void testApplyDiscountByLineItems_AppliesPercentageDiscount() {
        Map<String, List<PricingPaymentItem>> input =
            new Map<String, List<PricingPaymentItem>>{
                'LINE-1' => new List<PricingPaymentItem>{
                    paymentItem('DDA', 'T2216', '100.00')
                }
            };

        Test.startTest();
        Map<String, List<PricingPaymentItem>> result =
            SIAE_UTIL_VoceIncassoEngine.applyDiscountByLineItems(
                input,
                new Map<String, Decimal>{ 'LINE-1' => 0.20 }
            );
        Test.stopTest();

        System.assertEquals(1, result.get('LINE-1').size(), 'Deve restituire un solo PaymentItem per la riga');
        System.assertEquals(
            '80.00',
            result.get('LINE-1')[0].amount,
            'Sconto 20% su 100.00 deve dare 80.00'
        );
        System.assertEquals('T2216', result.get('LINE-1')[0].itemCode, 'itemCode deve restare invariato');
        System.assertEquals('DDA', result.get('LINE-1')[0].type, 'type deve restare invariato');
    }

    @IsTest
    static void testApplyDiscountByLineItems_ZeroOrNullDiscountLeavesItemsUnchanged() {
        Map<String, List<PricingPaymentItem>> input =
            new Map<String, List<PricingPaymentItem>>{
                'LINE-ZERO' => new List<PricingPaymentItem>{
                    paymentItem('DDA', 'T2216', '100.00')
                },
                'LINE-NULL' => new List<PricingPaymentItem>{
                    paymentItem('DDA', 'T2216', '100.00')
                }
            };

        Test.startTest();
        Map<String, List<PricingPaymentItem>> result =
            SIAE_UTIL_VoceIncassoEngine.applyDiscountByLineItems(
                input,
                new Map<String, Decimal>{ 'LINE-ZERO' => 0, 'LINE-NULL' => null }
            );
        Test.stopTest();

        System.assertEquals('100.00', result.get('LINE-ZERO')[0].amount, 'Discount 0 non deve modificare amount');
        System.assertEquals('100.00', result.get('LINE-NULL')[0].amount, 'Discount null non deve modificare amount');
    }

    @IsTest
    static void testApplyDiscountByLineItems_LineItemNotInDiscountMapLeftUnchanged() {
        Map<String, List<PricingPaymentItem>> input =
            new Map<String, List<PricingPaymentItem>>{
                'LINE-NO-DISCOUNT' => new List<PricingPaymentItem>{
                    paymentItem('DDA', 'T2216', '55.50')
                }
            };

        Test.startTest();
        Map<String, List<PricingPaymentItem>> result =
            SIAE_UTIL_VoceIncassoEngine.applyDiscountByLineItems(
                input,
                new Map<String, Decimal>()
            );
        Test.stopTest();

        System.assertEquals(
            '55.50',
            result.get('LINE-NO-DISCOUNT')[0].amount,
            'Senza voce nella discount map, amount deve restare invariato'
        );
    }

    @IsTest
    static void testApplyDiscountByLineItems_MultipleItemsSameLineAllDiscounted() {
        Map<String, List<PricingPaymentItem>> input =
            new Map<String, List<PricingPaymentItem>>{
                'LINE-MULTI' => new List<PricingPaymentItem>{
                    paymentItem('DDA', 'T2216', '100.00'),
                    paymentItem('DDA', 'T2217', '50.00')
                }
            };

        Test.startTest();
        Map<String, List<PricingPaymentItem>> result =
            SIAE_UTIL_VoceIncassoEngine.applyDiscountByLineItems(
                input,
                new Map<String, Decimal>{ 'LINE-MULTI' => 0.10 }
            );
        Test.stopTest();

        List<PricingPaymentItem> discounted = result.get('LINE-MULTI');
        System.assertEquals(2, discounted.size(), 'Devono restare 2 PaymentItem per la riga');
        System.assertEquals('90.00', discounted[0].amount, 'Primo item scontato del 10%');
        System.assertEquals('45.00', discounted[1].amount, 'Secondo item scontato del 10%');
    }

    @IsTest
    static void testApplyDiscountByLineItems_FullDiscountZeroesAmount() {
        Map<String, List<PricingPaymentItem>> input =
            new Map<String, List<PricingPaymentItem>>{
                'LINE-FULL' => new List<PricingPaymentItem>{
                    paymentItem('DDA', 'T2216', '20.00')
                }
            };

        Test.startTest();
        Map<String, List<PricingPaymentItem>> result =
            SIAE_UTIL_VoceIncassoEngine.applyDiscountByLineItems(
                input,
                new Map<String, Decimal>{ 'LINE-FULL' => 1 }
            );
        Test.stopTest();

        System.assertEquals(
            '0.00',
            result.get('LINE-FULL')[0].amount,
            'Sconto 100% deve azzerare amount (0.00, non null)'
        );
    }
}