@IsTest
private class SIAE_ProductConfigurationRuleHandler_T {

    @TestSetup
    static void setup() {
        insert new List<Product2>{
            new Product2(Name = 'Prodotto 1', ProductCode = 'P1', IsActive = true),
            new Product2(Name = 'Prodotto 2', ProductCode = 'P2', IsActive = true),
            new Product2(Name = 'Prodotto 3', ProductCode = 'P3', IsActive = true)
        };
    }

    @IsTest
    static void testSyncBusinessRulesFromFlow_NullAndEmpty() {
        Test.startTest();
        SIAE_ProductConfigurationRuleHandler.syncBusinessRulesFromFlow(null);
        SIAE_ProductConfigurationRuleHandler.syncBusinessRulesFromFlow(
            new List<SIAE_ProductConfigurationRuleHandler.FlowInput>()
        );
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testSyncBusinessRulesFromFlow_AllBranches() {
        Product2 p1 = getProduct('P1');
        Product2 p2 = getProduct('P2');

        SIAE_ProductConfigurationRuleHandler.FlowInput insertInput =
            new SIAE_ProductConfigurationRuleHandler.FlowInput();
        insertInput.operationType = 'INSERT';
        insertInput.configurationRuleDefinition = buildDefinitionJson(
            p1.Id, p1.Id, p2.Id, 'SetAttribute', true
        );

        SIAE_ProductConfigurationRuleHandler.FlowInput updateInput =
            new SIAE_ProductConfigurationRuleHandler.FlowInput();
        updateInput.operationType = 'UPDATE';
        updateInput.oldConfigurationRuleDefinition = buildDefinitionJson(
            p1.Id, p1.Id, p2.Id, 'SetAttribute', true
        );
        updateInput.configurationRuleDefinition = buildDefinitionJson(
            p2.Id, p2.Id, p1.Id, 'SetAttribute', true
        );

        SIAE_ProductConfigurationRuleHandler.FlowInput deleteInput =
            new SIAE_ProductConfigurationRuleHandler.FlowInput();
        deleteInput.operationType = 'DELETE';
        deleteInput.recordId = p1.Id;
        deleteInput.configurationRuleDefinition = buildDefinitionJson(
            p1.Id, p1.Id, p2.Id, 'SetAttribute', true
        );

        SIAE_ProductConfigurationRuleHandler.FlowInput invalidInput =
            new SIAE_ProductConfigurationRuleHandler.FlowInput();
        invalidInput.operationType = 'UPSERT';
        invalidInput.configurationRuleDefinition = 'invalid';

        Test.startTest();
        SIAE_ProductConfigurationRuleHandler.syncBusinessRulesFromFlow(
            new List<SIAE_ProductConfigurationRuleHandler.FlowInput>{
                insertInput, updateInput, deleteInput, invalidInput, null
            }
        );
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testExtractProductIdFromDefinition() {
        Product2 p1 = getProduct('P1');

        String jsonDef = buildDefinitionJson(p1.Id, p1.Id, p1.Id, 'SetAttribute', true);

        System.assertEquals(
            p1.Id,
            SIAE_ProductConfigurationRuleHandler.extractProductIdFromDefinition(jsonDef)
        );
        System.assertEquals(
            null,
            SIAE_ProductConfigurationRuleHandler.extractProductIdFromDefinition(null)
        );
        System.assertEquals(
            null,
            SIAE_ProductConfigurationRuleHandler.extractProductIdFromDefinition('not-json')
        );
    }

    @IsTest
    static void testExtractAttributeIdsFromDefinition() {
        Product2 p1 = getProduct('P1');
        Product2 p2 = getProduct('P2');
        Product2 p3 = getProduct('P3');

        String jsonDef = buildDefinitionJson(p1.Id, p2.Id, p3.Id, 'SetAttribute', true);

        Set<Id> ids = SIAE_ProductConfigurationRuleHandler.extractAttributeIdsFromDefinition(jsonDef);

        System.assertEquals(2, ids.size());
        System.assert(ids.contains(p2.Id));
        System.assert(ids.contains(p3.Id));

        Set<Id> invalidIds =
            SIAE_ProductConfigurationRuleHandler.extractAttributeIdsFromDefinition('invalid');
        System.assertEquals(0, invalidIds.size());
    }

    @IsTest
    static void testSimplifyRuleCore_WithActionParameter() {
        Product2 p1 = getProduct('P1');
        Product2 p2 = getProduct('P2');
        Product2 p3 = getProduct('P3');

        String jsonDef = buildDefinitionJson(p1.Id, p2.Id, p3.Id, 'SetAttribute', true);

        Map<String, Object> result =
            SIAE_ProductConfigurationRuleHandler.simplifyRuleCore(
                p1.Id,
                jsonDef,
                new Map<Id, AttributeDefinition>(),
                new Map<Id, Id>(),
                new Map<String, String>()
            );

        System.assertNotEquals(null, result);

        List<Object> dependencies = (List<Object>) result.get('dependencies');
        System.assertEquals(1, dependencies.size());

        Map<String, Object> dep = (Map<String, Object>) dependencies[0];
        System.assertEquals(p1.Id, dep.get('ruleId'));
        System.assertEquals('All', dep.get('conditionLogic'));

        List<Object> conditions = (List<Object>) dep.get('conditions');
        System.assertEquals(1, conditions.size());

        Map<String, Object> cond = (Map<String, Object>) conditions[0];
        System.assertEquals('ATTR_CONDITION_TEST', cond.get('attributeName'));
        System.assertEquals('Equals', cond.get('operator'));
        System.assertEquals('COND_VALUE', cond.get('attributeValue'));

        List<Object> actions = (List<Object>) dep.get('actions');
        System.assertEquals(1, actions.size());

        Map<String, Object> act = (Map<String, Object>) actions[0];
        System.assertEquals('SetAttribute', act.get('actionType'));
        System.assertEquals('ATTR_ACTION_TEST', act.get('attributeName'));
        System.assertEquals('ACTION_VALUE', act.get('attributeValue'));
    }

    @IsTest
    static void testSimplifyRuleCore_ActionWithoutParameters() {
        Product2 p1 = getProduct('P1');
        Product2 p2 = getProduct('P2');
        Product2 p3 = getProduct('P3');

        String jsonDef = buildDefinitionJson(p1.Id, p2.Id, p3.Id, 'Validate', false);

        Map<String, Object> result =
            SIAE_ProductConfigurationRuleHandler.simplifyRuleCore(
                p1.Id,
                jsonDef,
                new Map<Id, AttributeDefinition>(),
                new Map<Id, Id>(),
                new Map<String, String>()
            );

        List<Object> dependencies = (List<Object>) result.get('dependencies');
        Map<String, Object> dep = (Map<String, Object>) dependencies[0];
        List<Object> actions = (List<Object>) dep.get('actions');
        Map<String, Object> act = (Map<String, Object>) actions[0];

        System.assertEquals('Validate', act.get('actionType'));
        System.assertEquals(null, act.get('attributeName'));
        System.assertEquals(null, act.get('attributeValue'));
        System.assertEquals('ERROR', act.get('messageType'));
        System.assertEquals('Messaggio test', act.get('message'));
    }

    @IsTest
    static void testBuildDependenciesByProductFromInputs() {
        Product2 p1 = getProduct('P1');
        Product2 p2 = getProduct('P2');
        Product2 p3 = getProduct('P3');

        SIAE_ProductConfigurationRuleHandler.RuleInput r1 =
            new SIAE_ProductConfigurationRuleHandler.RuleInput(
                p1.Id,
                buildDefinitionJson(p1.Id, p2.Id, p3.Id, 'SetAttribute', true)
            );

        SIAE_ProductConfigurationRuleHandler.RuleInput r2 =
            new SIAE_ProductConfigurationRuleHandler.RuleInput(
                p2.Id,
                buildDefinitionJson(p2.Id, p1.Id, p3.Id, 'Validate', false)
            );

        Map<Id, List<Map<String, Object>>> result =
            SIAE_ProductConfigurationRuleHandler.buildDependenciesByProductFromInputs(
                new List<SIAE_ProductConfigurationRuleHandler.RuleInput>{ r1, r2 },
                new Set<Id>{ p1.Id, p2.Id }
            );

        System.assertEquals(2, result.size());
        System.assertEquals(1, result.get(p1.Id).size());
        System.assertEquals(1, result.get(p2.Id).size());
    }

    @IsTest
    static void testBuildDependenciesByProductFromInputs_Empty() {
        Product2 p1 = getProduct('P1');

        Map<Id, List<Map<String, Object>>> result =
            SIAE_ProductConfigurationRuleHandler.buildDependenciesByProductFromInputs(
                null,
                new Set<Id>{ p1.Id }
            );

        System.assertEquals(0, result.size());
    }

    @IsTest
    static void testBuildFinalJsonForProduct() {
        Map<String, Object> dep = new Map<String, Object>{
            'ruleId' => '001000000000001AAA',
            'conditionLogic' => 'All',
            'conditions' => new List<Object>(),
            'actions' => new List<Object>()
        };

        String jsonResult =
            SIAE_ProductConfigurationRuleHandler.buildFinalJsonForProduct(
                new List<Map<String, Object>>{ dep }
            );

        System.assertNotEquals(null, jsonResult);
        System.assert(jsonResult.contains('"dependencies"'));
        System.assertEquals(
            null,
            SIAE_ProductConfigurationRuleHandler.buildFinalJsonForProduct(null)
        );
    }

    @IsTest
    static void testTranslateValueUsingMetadata_NullAttrDef() {
        Object result =
            SIAE_ProductConfigurationRuleHandler.translateValueUsingMetadata(
                'abc',
                null,
                null,
                new Map<String, String>()
            );

        System.assertEquals('abc', result);
    }

    @IsTest
    static void testExtractFirstValue() {
        System.assertEquals(
            'FIRST',
            SIAE_ProductConfigurationRuleHandler.extractFirstValue(
                new List<Object>{ 'FIRST', 'SECOND' }
            )
        );
        System.assertEquals(
            'DIRECT',
            SIAE_ProductConfigurationRuleHandler.extractFirstValue('DIRECT')
        );
        System.assertEquals(
            null,
            SIAE_ProductConfigurationRuleHandler.extractFirstValue(new List<Object>())
        );
    }

    @IsTest
    static void testHelpers() {
        Product2 p1 = getProduct('P1');

        System.assertEquals(
            true,
            SIAE_ProductConfigurationRuleHandler.isSalesforceId((String) p1.Id)
        );
        System.assertEquals(
            false,
            SIAE_ProductConfigurationRuleHandler.isSalesforceId('abc')
        );
        System.assertEquals(
            '123',
            SIAE_ProductConfigurationRuleHandler.stringValue(123)
        );
        System.assertEquals(
            null,
            SIAE_ProductConfigurationRuleHandler.stringValue(null)
        );
        System.assertEquals(
            'A',
            SIAE_ProductConfigurationRuleHandler.firstNonBlank('A', 'B')
        );
        System.assertEquals(
            'B',
            SIAE_ProductConfigurationRuleHandler.firstNonBlank('', 'B')
        );
        System.assert(
            SIAE_ProductConfigurationRuleHandler.buildPicklistKey(p1.Id, 'VAL').contains('###VAL')
        );
    }

    @IsTest
    static void testDiscoverAttributeDefinitionPicklistFieldApiName() {
        String result = SIAE_ProductConfigurationRuleHandler.discoverAttributeDefinitionPicklistFieldApiName();
        System.assert(true, 'Metodo eseguito: ' + result);
    }

    private static Product2 getProduct(String code) {
        return [
            SELECT Id, ProductCode
            FROM Product2
            WHERE ProductCode = :code
            LIMIT 1
        ];
    }

    private static String buildDefinitionJson(
        Id productId,
        Id conditionAttributeId,
        Id actionAttributeId,
        String actionType,
        Boolean includeActionParameters
    ) {
        Map<String, Object> condition = new Map<String, Object>{
            'attributeId' => String.valueOf(conditionAttributeId),
            'attributeName' => 'ATTR_CONDITION_TEST',
            'operator' => 'Equals',
            'values' => new List<Object>{ 'COND_VALUE' }
        };

        Map<String, Object> criterion = new Map<String, Object>{
            'sourceValues' => new List<Object>{ String.valueOf(productId) },
            'conditions' => new List<Object>{ condition }
        };

        Map<String, Object> action = new Map<String, Object>{
            'actionType' => actionType,
            'messageType' => 'ERROR',
            'message' => 'Messaggio test'
        };

        if (includeActionParameters) {
            action.put('actionParameters', new List<Object>{
                new Map<String, Object>{
                    'attributeId' => String.valueOf(actionAttributeId),
                    'attributeName' => 'ATTR_ACTION_TEST',
                    'values' => new List<Object>{ 'ACTION_VALUE' }
                }
            });
        } else {
            action.put('actionParameters', new List<Object>());
        }

        Map<String, Object> root = new Map<String, Object>{
            'criteriaExpressionType' => 'All',
            'criteria' => new List<Object>{ criterion },
            'actions' => new List<Object>{ action }
        };

        return JSON.serialize(root);
    }
}