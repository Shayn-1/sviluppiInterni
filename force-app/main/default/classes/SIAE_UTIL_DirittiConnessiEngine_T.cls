/**
 * @description       : Test class for SIAE_UTIL_DirittiConnessiEngine
 * @author            : Iuliano Gaetano - gaetano.iuliano@nttdata.com
 * @last modified on  : 20/05/2026
**/
@isTest
private class SIAE_UTIL_DirittiConnessiEngine_T {
    
    private static final String TEST_PRODUCT_CODE = 'SIAE-PROD-ACCONCIATORI';
    private static final String TEST_FAMILY = 'Test Family';
    private static final String TEST_CONFIG_NAME = 'Acconciatori';
    
    /**
     * @description Setup test data
     */
    @testSetup
    static void setupData() {
        // Create Product2
        Product2 testProduct = new Product2(
            Name = 'Test Product',
            ProductCode = TEST_PRODUCT_CODE,
            Family = TEST_FAMILY,
            IsActive = true
        );
        insert testProduct;
        
        // Create SIAE_DirittiConnessiTariffa__c records
        List<SIAE_DirittiConnessiTariffa__c> tariffe = new List<SIAE_DirittiConnessiTariffa__c>{
            new SIAE_DirittiConnessiTariffa__c(
                Name = 'Tariffa 1',
                SIAE_ConfigName__c = TEST_CONFIG_NAME,
                SIAE_DeviceType__c = 'Audio',
                SIAE_BracketFrom__c = 0,
                SIAE_BracketTo__c = 10,
                SIAE_Amount__c = 100,
                SIAE_ExtraAmountPerUnit__c = 10,
                SIAE_ExtraUnitSize__c = 1,
                SIAE_ExtraPercentage__c = 5
            ),
            new SIAE_DirittiConnessiTariffa__c(
                Name = 'Tariffa 2',
                SIAE_ConfigName__c = TEST_CONFIG_NAME,
                SIAE_DeviceType__c = 'Video',
                SIAE_BracketFrom__c = 0,
                SIAE_BracketTo__c = 5,
                SIAE_Amount__c = 200,
                SIAE_ExtraAmountPerUnit__c = 20,
                SIAE_ExtraUnitSize__c = 1,
                SIAE_ExtraPercentage__c = 10
            )
        };
        insert tariffe;
        
        // Create SIAE_DirittiConnessiRule__c records using SObject.put for type-safety
        List<SObject> regoleToInsert = new List<SObject>();
        
        // Safer approach: insert base records without ambiguous typed fields, then attempt update with Decimal values.
        List<SObject> baseRegole = new List<SObject>();
        
        // Use explicit, known-valid picklist values provided by user: GT and BETWEEN
        String operatorValue1 = 'GT';
        String operatorValue2 = 'BETWEEN';
        
        // Use action picklist values that exist in the org (provided list). We'll map test intentions to valid values.
        // Mapping: ADD_PERCENTAGE -> MAGGIORAZIONE_PCT, SET_AMOUNT -> TARIFFA_BASE
        String actionForRule1 = 'MAGGIORAZIONE_PCT';
        String actionForRule2 = 'TARIFFA_BASE';
        
        SObject base1 = Schema.getGlobalDescribe().get('SIAE_DirittiConnessiRule__c').newSObject();
        base1.put('Name', 'Rule 1');
        base1.put('SIAE_LicenseConfig__c', TEST_CONFIG_NAME);
        base1.put('SIAE_Order__c', 1);
        base1.put('SIAE_Attribute__c', 'SIAE-ATTR-QTA');
        base1.put('SIAE_Operator__c', operatorValue1);
        base1.put('SIAE_DeviceType__c', 'Audio');
        base1.put('SIAE_Action__c', actionForRule1);
        baseRegole.add(base1);
        
        SObject base2 = Schema.getGlobalDescribe().get('SIAE_DirittiConnessiRule__c').newSObject();
        base2.put('Name', 'Rule 2');
        base2.put('SIAE_LicenseConfig__c', TEST_CONFIG_NAME);
        base2.put('SIAE_Order__c', 2);
        base2.put('SIAE_Attribute__c', 'SIAE-ATTR-QTA');
        base2.put('SIAE_Operator__c', operatorValue2);
        base2.put('SIAE_DeviceType__c', 'Video');
        base2.put('SIAE_Action__c', actionForRule2);
        baseRegole.add(base2);
        
        insert baseRegole;
        
        // Deterministic handling based on provided field types:
        // SIAE_ValueFrom__c  -> String
        // SIAE_ValueTo__c    -> String
        // SIAE_ActionValue__c -> Decimal
        List<SObject> toUpdate = new List<SObject>();
        for (SObject so : baseRegole) {
            SObject upd = Schema.getGlobalDescribe().get('SIAE_DirittiConnessiRule__c').newSObject();
            upd.put('Id', so.get('Id'));
            if (String.valueOf(so.get('Name')).contains('Rule 1')) {
                // ValueFrom (string) and ActionValue (decimal) for Rule 1
                upd.put('SIAE_ValueFrom__c', '5');
                upd.put('SIAE_ActionValue__c', Decimal.valueOf('10'));
            } else {
                // Rule 2: ValueFrom, ValueTo as strings; ActionValue as decimal
                upd.put('SIAE_ValueFrom__c', '1');
                upd.put('SIAE_ValueTo__c', '10');
                upd.put('SIAE_ActionValue__c', Decimal.valueOf('150'));
            }
            toUpdate.add(upd);
        }
        // Single update with deterministic types
        update toUpdate;
    }
    
    /**
     * @description Test calculate method with valid data
     */
    @isTest
    static void testCalculate_Success() {
        Product2 testProduct = [SELECT Id, ProductCode FROM Product2 LIMIT 1];
        
        Map<String, Product2> mapProductIdProduct = new Map<String, Product2>{
            testProduct.Id => testProduct
        };
        
        Set<String> setOfProductCode = new Set<String>{ TEST_PRODUCT_CODE };
        
        List<RCASalesTransaction.ItemNode> listOfSalesItemNode = 
            new List<RCASalesTransaction.ItemNode>();
        
        RCASalesTransaction.ItemNode node = 
            new RCASalesTransaction.ItemNode();
        node.productId = testProduct.Id;
        node.lineItemId = 'test-line-item-001';
        node.netTotalPrice = 1000;
        node.attributeValueByCode = new Map<String, String>{
            'SIAE-ATTR-QTA' => '8',
            'SIAE-ATTR-AUDIO' => '2',
            'SIAE-ATTR-VIDEO' => '1'
        };
        
        listOfSalesItemNode.add(node);
        
        Test.startTest();
        SIAE_DTO_DirittiConnessiResult result = SIAE_UTIL_DirittiConnessiEngine.calculate(
            listOfSalesItemNode,
            setOfProductCode,
            mapProductIdProduct
        );
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertNotEquals(null, result.dettagliPerOrderItem, 'Details should not be null');
    }
    
    /**
     * @description Test calculate method with null input list
     */
    @isTest
    static void testCalculate_NullInputList() {
        Set<String> setOfProductCode = new Set<String>{ TEST_PRODUCT_CODE };
        Map<String, Product2> mapProductIdProduct = new Map<String, Product2>();
        
        Test.startTest();
        SIAE_DTO_DirittiConnessiResult result = SIAE_UTIL_DirittiConnessiEngine.calculate(
            null,
            setOfProductCode,
            mapProductIdProduct
        );
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.totaleComplessivo, 'Total should be 0');
        System.assertEquals(0, result.dettagliPerOrderItem.size(), 'Details should be empty');
    }
    
    /**
     * @description Test calculate method with empty input list
     */
    @isTest
    static void testCalculate_EmptyInputList() {
        Set<String> setOfProductCode = new Set<String>{ TEST_PRODUCT_CODE };
        Map<String, Product2> mapProductIdProduct = new Map<String, Product2>();
        
        Test.startTest();
        SIAE_DTO_DirittiConnessiResult result = SIAE_UTIL_DirittiConnessiEngine.calculate(
            new List<RCASalesTransaction.ItemNode>(),
            setOfProductCode,
            mapProductIdProduct
        );
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.totaleComplessivo, 'Total should be 0');
        System.assertEquals(0, result.dettagliPerOrderItem.size(), 'Details should be empty');
    }
    
    /**
     * @description Test calculate method with empty product code set
     */
    @isTest
    static void testCalculate_EmptyProductCodeSet() {
        Product2 testProduct = [SELECT Id FROM Product2 LIMIT 1];
        
        List<RCASalesTransaction.ItemNode> listOfSalesItemNode = 
            new List<RCASalesTransaction.ItemNode>();
        
        RCASalesTransaction.ItemNode node = 
            new RCASalesTransaction.ItemNode();
        node.productId = testProduct.Id;
        listOfSalesItemNode.add(node);
        
        Set<String> emptyProductCodeSet = new Set<String>();
        Map<String, Product2> mapProductIdProduct = new Map<String, Product2>();
        
        Test.startTest();
        SIAE_DTO_DirittiConnessiResult result = SIAE_UTIL_DirittiConnessiEngine.calculate(
            listOfSalesItemNode,
            emptyProductCodeSet,
            mapProductIdProduct
        );
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.totaleComplessivo, 'Total should be 0');
        System.assertEquals(0, result.dettagliPerOrderItem.size(), 'Details should be empty');
    }
    
    /**
     * @description Test calculate method with disabled configuration
     */
    @isTest
    static void testCalculate_DisabledConfig() {
        // SIAE-PROD-AEREI is disabled in Custom Metadata
        String disabledProductCode = 'SIAE-PROD-AEREI';
        Product2 testProduct = new Product2(
            Name = 'Disabled Product',
            ProductCode = disabledProductCode,
            IsActive = true
        );
        insert testProduct;
        
        Map<String, Product2> mapProductIdProduct = new Map<String, Product2>{
            testProduct.Id => testProduct
        };
        
        Set<String> setOfProductCode = new Set<String>{ disabledProductCode };
        
        List<RCASalesTransaction.ItemNode> listOfSalesItemNode = 
            new List<RCASalesTransaction.ItemNode>();
        
        RCASalesTransaction.ItemNode node = 
            new RCASalesTransaction.ItemNode();
        node.productId = testProduct.Id;
        node.lineItemId = 'test-line-item-disabled';
        listOfSalesItemNode.add(node);
        
        Test.startTest();
        SIAE_DTO_DirittiConnessiResult result = SIAE_UTIL_DirittiConnessiEngine.calculate(
            listOfSalesItemNode,
            setOfProductCode,
            mapProductIdProduct
        );
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.dettagliPerOrderItem.size(), 'Should skip disabled config');
    }
    
    /**
     * @description Test calculate method with no configuration
     */
    @isTest
    static void testCalculate_NoConfig() {
        String noConfigProductCode = 'NO-CONFIG-PROD';
        Product2 testProduct = new Product2(
            Name = 'No Config Product',
            ProductCode = noConfigProductCode,
            IsActive = true
        );
        insert testProduct;
        
        Map<String, Product2> mapProductIdProduct = new Map<String, Product2>{
            testProduct.Id => testProduct
        };
        
        Set<String> setOfProductCode = new Set<String>{ noConfigProductCode };
        
        List<RCASalesTransaction.ItemNode> listOfSalesItemNode = 
            new List<RCASalesTransaction.ItemNode>();
        
        RCASalesTransaction.ItemNode node = 
            new RCASalesTransaction.ItemNode();
        node.productId = testProduct.Id;
        node.lineItemId = 'test-line-item-no-config';
        listOfSalesItemNode.add(node);
        
        Test.startTest();
        SIAE_DTO_DirittiConnessiResult result = SIAE_UTIL_DirittiConnessiEngine.calculate(
            listOfSalesItemNode,
            setOfProductCode,
            mapProductIdProduct
        );
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.dettagliPerOrderItem.size(), 'Should skip missing config');
    }
    
    /**
     * @description Test calculate method with no rules and no tariffe
     */
    @isTest
    static void testCalculate_NoRulesNoTariffe() {
        // SIAE-PROD-AGRITURISMI is enabled but we don't insert rules/tariffe for it in this test
        String enabledProductCode = 'SIAE-PROD-AGRITURISMI';
        Product2 testProduct = new Product2(
            Name = 'Enabled No Rules Product',
            ProductCode = enabledProductCode,
            IsActive = true
        );
        insert testProduct;
        
        Map<String, Product2> mapProductIdProduct = new Map<String, Product2>{
            testProduct.Id => testProduct
        };
        
        Set<String> setOfProductCode = new Set<String>{ enabledProductCode };
        
        List<RCASalesTransaction.ItemNode> listOfSalesItemNode = 
            new List<RCASalesTransaction.ItemNode>();
        
        RCASalesTransaction.ItemNode node = 
            new RCASalesTransaction.ItemNode();
        node.productId = testProduct.Id;
        node.lineItemId = 'test-line-item-no-rules';
        listOfSalesItemNode.add(node);
        
        Test.startTest();
        SIAE_DTO_DirittiConnessiResult result = SIAE_UTIL_DirittiConnessiEngine.calculate(
            listOfSalesItemNode,
            setOfProductCode,
            mapProductIdProduct
        );
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        // It should still process but with empty rules/tariffe
        System.assertEquals(1, result.dettagliPerOrderItem.size(), 'Should have one detail entry');
    }

    /**
     * @description Test calculate method with blank productId
     */
    @isTest
    static void testCalculate_BlankProductId() {
        Set<String> setOfProductCode = new Set<String>{ TEST_PRODUCT_CODE };
        Map<String, Product2> mapProductIdProduct = new Map<String, Product2>();
        
        List<RCASalesTransaction.ItemNode> listOfSalesItemNode = 
            new List<RCASalesTransaction.ItemNode>();
        
        RCASalesTransaction.ItemNode node = 
            new RCASalesTransaction.ItemNode();
        node.productId = '';
        node.lineItemId = 'test-line-item-001';
        listOfSalesItemNode.add(node);
        
        Test.startTest();
        SIAE_DTO_DirittiConnessiResult result = SIAE_UTIL_DirittiConnessiEngine.calculate(
            listOfSalesItemNode,
            setOfProductCode,
            mapProductIdProduct
        );
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.dettagliPerOrderItem.size(), 'No details should be processed');
    }
    
    /**
     * @description Test calculate method with product not in map
     */
    @isTest
    static void testCalculate_ProductNotInMap() {
        Set<String> setOfProductCode = new Set<String>{ TEST_PRODUCT_CODE };
        Map<String, Product2> mapProductIdProduct = new Map<String, Product2>();
        
        List<RCASalesTransaction.ItemNode> listOfSalesItemNode = 
            new List<RCASalesTransaction.ItemNode>();
        
        RCASalesTransaction.ItemNode node = 
            new RCASalesTransaction.ItemNode();
        node.productId = 'non-existent-product-id';
        node.lineItemId = 'test-line-item-001';
        listOfSalesItemNode.add(node);
        
        Test.startTest();
        SIAE_DTO_DirittiConnessiResult result = SIAE_UTIL_DirittiConnessiEngine.calculate(
            listOfSalesItemNode,
            setOfProductCode,
            mapProductIdProduct
        );
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.dettagliPerOrderItem.size(), 'No details should be processed');
    }
    
    /**
     * @description Test calculate method with null attributeValueByCode
     */
    @isTest
    static void testCalculate_NullAttributeValueByCode() {
        Product2 testProduct = [SELECT Id, ProductCode FROM Product2 LIMIT 1];
        
        Map<String, Product2> mapProductIdProduct = new Map<String, Product2>{
            testProduct.Id => testProduct
        };
        
        Set<String> setOfProductCode = new Set<String>{ TEST_PRODUCT_CODE };
        
        List<RCASalesTransaction.ItemNode> listOfSalesItemNode = 
            new List<RCASalesTransaction.ItemNode>();
        
        RCASalesTransaction.ItemNode node = 
            new RCASalesTransaction.ItemNode();
        node.productId = testProduct.Id;
        node.lineItemId = 'test-line-item-001';
        node.netTotalPrice = 1000;
        node.attributeValueByCode = null;
        
        listOfSalesItemNode.add(node);
        
        Test.startTest();
        SIAE_DTO_DirittiConnessiResult result = SIAE_UTIL_DirittiConnessiEngine.calculate(
            listOfSalesItemNode,
            setOfProductCode,
            mapProductIdProduct
        );
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
    }
    
    /**
     * @description Test loadConfigs method with valid product codes
     */
    @isTest
    static void testLoadConfigs_Success() {
        Set<String> productCodes = new Set<String>{ TEST_PRODUCT_CODE };
        
        Test.startTest();
        Map<String, SIAE_DirittiConnessiConfig__mdt> result = 
            SIAE_UTIL_DirittiConnessiEngine.loadConfigs(productCodes);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
    }
    
    /**
     * @description Test loadConfigs method with null input
     */
    @isTest
    static void testLoadConfigs_NullInput() {
        Test.startTest();
        Map<String, SIAE_DirittiConnessiConfig__mdt> result = 
            SIAE_UTIL_DirittiConnessiEngine.loadConfigs(null);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.size(), 'Result should be empty');
    }
    
    /**
     * @description Test loadConfigs method with empty set
     */
    @isTest
    static void testLoadConfigs_EmptySet() {
        Set<String> emptySet = new Set<String>();
        
        Test.startTest();
        Map<String, SIAE_DirittiConnessiConfig__mdt> result = 
            SIAE_UTIL_DirittiConnessiEngine.loadConfigs(emptySet);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.size(), 'Result should be empty');
    }
    
    /**
     * @description Test loadTariffe method with valid config names
     */
    @isTest
    static void testLoadTariffe_Success() {
        Set<String> configNames = new Set<String>{ TEST_CONFIG_NAME };
        
        Test.startTest();
        Map<String, List<SIAE_DirittiConnessiTariffa__c>> result = 
            SIAE_UTIL_DirittiConnessiEngine.loadTariffe(configNames);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.containsKey(TEST_CONFIG_NAME), 'Should contain test config');
        System.assertEquals(2, result.get(TEST_CONFIG_NAME).size(), 'Should have 2 tariffe');
    }
    
    /**
     * @description Test loadTariffe method with null input
     */
    @isTest
    static void testLoadTariffe_NullInput() {
        Test.startTest();
        Map<String, List<SIAE_DirittiConnessiTariffa__c>> result = 
            SIAE_UTIL_DirittiConnessiEngine.loadTariffe(null);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.size(), 'Result should be empty');
    }
    
    /**
     * @description Test loadTariffe method with empty set
     */
    @isTest
    static void testLoadTariffe_EmptySet() {
        Set<String> emptySet = new Set<String>();
        
        Test.startTest();
        Map<String, List<SIAE_DirittiConnessiTariffa__c>> result = 
            SIAE_UTIL_DirittiConnessiEngine.loadTariffe(emptySet);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.size(), 'Result should be empty');
    }
    
    /**
     * @description Test loadRegole method with valid config names
     */
    @isTest
    static void testLoadRegole_Success() {
        Set<String> configNames = new Set<String>{ TEST_CONFIG_NAME };
        
        Test.startTest();
        Map<String, List<SIAE_DirittiConnessiRule__c>> result = 
            SIAE_UTIL_DirittiConnessiEngine.loadRegole(configNames);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.containsKey(TEST_CONFIG_NAME), 'Should contain test config');
        System.assertEquals(2, result.get(TEST_CONFIG_NAME).size(), 'Should have 2 regole');
    }
    
    /**
     * @description Test loadRegole method with null input
     */
    @isTest
    static void testLoadRegole_NullInput() {
        Test.startTest();
        Map<String, List<SIAE_DirittiConnessiRule__c>> result = 
            SIAE_UTIL_DirittiConnessiEngine.loadRegole(null);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.size(), 'Result should be empty');
    }
    
    /**
     * @description Test loadRegole method with empty set
     */
    @isTest
    static void testLoadRegole_EmptySet() {
        Set<String> emptySet = new Set<String>();
        
        Test.startTest();
        Map<String, List<SIAE_DirittiConnessiRule__c>> result = 
            SIAE_UTIL_DirittiConnessiEngine.loadRegole(emptySet);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.size(), 'Result should be empty');
    }
    
    /**
     * @description Test groupAttributes method with valid attributes
     */
    @isTest
    static void testGroupAttributes_Success() {
        // Create test Account, Order, Product, and OrderItem
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;
        
        Id pricebookId = Test.getStandardPricebookId();
        
        Product2 testProduct = [SELECT Id FROM Product2 LIMIT 1];
        
        PricebookEntry testPbe = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = testProduct.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert testPbe;
        
        Order testOrder = new Order(
            AccountId = testAccount.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = pricebookId
        );
        insert testOrder;
        
        OrderItem testOrderItem = new OrderItem(
            OrderId = testOrder.Id,
            Product2Id = testProduct.Id,
            PricebookEntryId = testPbe.Id,
            Quantity = 1,
            UnitPrice = 100
        );
        insert testOrderItem;
        
        // Mocking using JSON to handle cross-object reference (AttributeDefinition.Code)
        // because AttributeDefinition/OrderItemAttribute might not support DML in all environments (e.g. Big Objects).
        String mockedJson = '[{' +
            '"OrderItemId": "' + testOrderItem.Id + '",' +
            '"AttributeValue": "Test Value",' +
            '"AttributeDefinition": {"Code": "TEST_ATTR"}' +
            '}]';
        List<OrderItemAttribute> attributesForMethod = (List<OrderItemAttribute>) JSON.deserialize(mockedJson, List<OrderItemAttribute>.class);
        
        Test.startTest();
        Map<Id, Map<String, String>> result = SIAE_UTIL_DirittiConnessiEngine.groupAttributes(attributesForMethod);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.containsKey(testOrderItem.Id), 'Should contain the item');
        System.assertEquals('Test Value', result.get(testOrderItem.Id).get('TEST_ATTR'), 'Should have correct value');
    }
    
    /**
     * @description Test groupAttributes method with null input
     */
    @isTest
    static void testGroupAttributes_NullInput() {
        Test.startTest();
        Map<Id, Map<String, String>> result = 
            SIAE_UTIL_DirittiConnessiEngine.groupAttributes(null);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.size(), 'Result should be empty');
    }
    
    /**
     * @description Test groupAttributes method with empty list
     */
    @isTest
    static void testGroupAttributes_EmptyList() {
        Test.startTest();
        Map<Id, Map<String, String>> result = 
            SIAE_UTIL_DirittiConnessiEngine.groupAttributes(new List<OrderItemAttribute>());
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.size(), 'Result should be empty');
    }
}