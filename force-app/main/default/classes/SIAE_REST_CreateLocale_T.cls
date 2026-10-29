/**
 * @description       Test class for SIAE_REST_CreateLocale
 * @author            Gaetano Iuliano - gaetano.iuliano@nttdata.com
 * @group             NTT Data — SIAE
 * @createdDate       2026-06-15
 * @lastModifiedDate  2026-07-31
 * @lastModifiedBy    Gaetano Iuliano
 */
@isTest
private class SIAE_REST_CreateLocale_T {

    // CMT SIAE_GenereLocale.G02_Sala → GenereName='Sala', ProductCode='SIAE-PROD-FOYER', GenereCode='02'
    private static final String TEST_GENERE_NAME  = 'Sala';
    private static final String TEST_PRODUCT_CODE = 'SIAE-PROD-FOYER';
    private static final String TEST_LOCAL_NAME   = 'Locale di Test';
    private static final String TEST_EGON_CIV     = '99887766';
    private static final String TEST_SEPRAG       = '1205878';
    private static final Long   TEST_LOCALE_ID    = 987654L;
    private static final Long   TEST_SPAZIO_ID    = 111222L;
    // spazio.denominazione = «Spazio <nome genere della riga>»: il prefisso è la costante
    // SPACE_NAME_PREFIX di SIAE_REST_CreateLocale, non è configurabile.
    private static final String EXPECTED_SPACE_PREFIX = 'Spazio';
    private static final String EXPECTED_SPACE_NAME   = EXPECTED_SPACE_PREFIX + ' ' + TEST_GENERE_NAME;

    @testSetup
    static void setupData() {
        Account acc = new Account(Name = 'Test Account CL');
        insert acc;

        Id pricebookId = Test.getStandardPricebookId();

        Product2 prod = new Product2(
            Name        = 'Prodotto Sala Test',
            ProductCode = TEST_PRODUCT_CODE,
            IsActive    = true
        );
        insert prod;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id   = prod.Id,
            UnitPrice    = 100,
            IsActive     = true
        );
        insert pbe;

        Order ord = new Order(
            AccountId        = acc.Id,
            EffectiveDate    = Date.today(),
            Status           = 'Draft',
            Pricebook2Id     = pricebookId,
            SIAE_LocalName__c = TEST_LOCAL_NAME,
            SIAE_IdEgonCiv__c = TEST_EGON_CIV,
            SIAE_Seprag__c    = TEST_SEPRAG
        );
        insert ord;

        OrderItem oi = new OrderItem(
            OrderId          = ord.Id,
            Product2Id       = prod.Id,
            PricebookEntryId = pbe.Id,
            Quantity         = 1,
            UnitPrice        = 100,
            SIAE_GenereName__c = TEST_GENERE_NAME
        );
        insert oi;
    }

    // Crea un Order (con/senza i campi di testata) + 1 OrderItem e restituisce l'OrderItem Id,
    // che è l'inputRecordId atteso da executeCallout.
    private static Id createOrderItem(Boolean withLocalName, Boolean withEgonCiv) {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        PricebookEntry pbe = [
            SELECT Id, Product2Id FROM PricebookEntry
            WHERE Product2.ProductCode = :TEST_PRODUCT_CODE LIMIT 1
        ];

        Order ord = new Order(
            AccountId         = acc.Id,
            EffectiveDate     = Date.today(),
            Status            = 'Draft',
            Pricebook2Id      = Test.getStandardPricebookId(),
            SIAE_LocalName__c = withLocalName ? TEST_LOCAL_NAME : null,
            SIAE_IdEgonCiv__c = withEgonCiv ? TEST_EGON_CIV : null,
            SIAE_Seprag__c    = TEST_SEPRAG
        );
        insert ord;

        OrderItem oi = new OrderItem(
            OrderId          = ord.Id,
            Product2Id       = pbe.Product2Id,
            PricebookEntryId = pbe.Id,
            Quantity         = 1,
            UnitPrice        = 100,
            SIAE_GenereName__c = TEST_GENERE_NAME
        );
        insert oi;
        return oi.Id;
    }

    // ────────────────────────────────────────────────────
    // getProviderAttributes
    // ────────────────────────────────────────────────────

    @isTest
    static void testGetProviderAttributes() {
        Test.startTest();
        List<industriesintegrationfwk.ApexProviderAttr> attrs =
            SIAE_REST_CreateLocale.getProviderAttributes();
        Test.stopTest();

        System.assertNotEquals(null, attrs, 'Attributes must not be null');
        System.assertEquals(1, attrs.size(), 'Expected exactly 1 attribute');
    }

    // ────────────────────────────────────────────────────
    // executeCallout — validation error paths
    // ────────────────────────────────────────────────────

    @isTest
    static void testExecuteCallout_BlankInputRecordId() {
        Test.startTest();
        industriesintegrationfwk.IntegrationCalloutResponse res =
            SIAE_REST_CreateLocale.executeCallout('guid', '', '', null, null);
        Test.stopTest();

        System.assertEquals(false, res.isSuccess());
        System.assertEquals(500, res.getResponseCode());
        System.assert(res.getErrorMessage().contains('inputRecordId is required'),
            'Error must mention inputRecordId');
    }

    @isTest
    static void testExecuteCallout_NullInputRecordId() {
        Test.startTest();
        industriesintegrationfwk.IntegrationCalloutResponse res =
            SIAE_REST_CreateLocale.executeCallout('guid', null, '', null, null);
        Test.stopTest();

        System.assertEquals(false, res.isSuccess());
        System.assertEquals(500, res.getResponseCode());
    }

    @isTest
    static void testExecuteCallout_WrongSObjectType() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        industriesintegrationfwk.IntegrationCalloutResponse res =
            SIAE_REST_CreateLocale.executeCallout('guid', acc.Id, '', null, null);
        Test.stopTest();

        System.assertEquals(false, res.isSuccess());
        System.assertEquals(500, res.getResponseCode());
        System.assert(res.getErrorMessage().contains('must be an OrderItem ID'),
            'Error must mention OrderItem ID');
    }

    @isTest
    static void testExecuteCallout_MissingLocalName() {
        Id oiId = createOrderItem(false, true);

        Test.startTest();
        industriesintegrationfwk.IntegrationCalloutResponse res =
            SIAE_REST_CreateLocale.executeCallout('guid', oiId, '', null, null);
        Test.stopTest();

        System.assertEquals(false, res.isSuccess());
        System.assertEquals(500, res.getResponseCode());
        System.assert(res.getErrorMessage().contains('SIAE_LocalName__c is required'),
            'Error must mention LocalName');
    }

    @isTest
    static void testExecuteCallout_MissingIdEgonCiv() {
        Id oiId = createOrderItem(true, false);

        Test.startTest();
        industriesintegrationfwk.IntegrationCalloutResponse res =
            SIAE_REST_CreateLocale.executeCallout('guid', oiId, '', null, null);
        Test.stopTest();

        System.assertEquals(false, res.isSuccess());
        System.assertEquals(500, res.getResponseCode());
        System.assert(res.getErrorMessage().contains('SIAE_IdEgonCiv__c is required'),
            'Error must mention IdEgonCiv');
    }

    // ────────────────────────────────────────────────────
    // executeCallout — HTTP 200 success
    // ────────────────────────────────────────────────────

    @isTest
    static void testExecuteCallout_Success() {
        Order ord = [SELECT Id FROM Order WHERE SIAE_LocalName__c = :TEST_LOCAL_NAME LIMIT 1];
        OrderItem oi = [SELECT Id FROM OrderItem WHERE OrderId = :ord.Id LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new MockSuccess(oi.Id));

        Map<String, Object> attrs = new Map<String, Object>{
            'integrationConfigName' => 'CreateLocale'
        };

        Test.startTest();
        industriesintegrationfwk.IntegrationCalloutResponse res =
            SIAE_REST_CreateLocale.executeCallout('guid', oi.Id, '', attrs, null);
        Test.stopTest();

        System.assertEquals(true, res.isSuccess(), 'Callout must succeed');
        System.assertEquals(200, res.getResponseCode());

        Order updOrd = [SELECT SIAE_LocaleId__c FROM Order WHERE Id = :ord.Id];
        System.assertEquals(String.valueOf(TEST_LOCALE_ID), updOrd.SIAE_LocaleId__c,
            'LocaleId must be written back');

        OrderItem updOi = [SELECT SIAE_SpaceId__c FROM OrderItem WHERE Id = :oi.Id];
        System.assertEquals(String.valueOf(TEST_SPAZIO_ID), updOi.SIAE_SpaceId__c,
            'SpaceId must be written back');
    }

    @isTest
    static void testExecuteCallout_NullAttributes() {
        Order ord = [SELECT Id FROM Order WHERE SIAE_LocalName__c = :TEST_LOCAL_NAME LIMIT 1];
        OrderItem oi = [SELECT Id FROM OrderItem WHERE OrderId = :ord.Id LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new MockSuccess(oi.Id));

        Test.startTest();
        industriesintegrationfwk.IntegrationCalloutResponse res =
            SIAE_REST_CreateLocale.executeCallout('guid', oi.Id, '', null, null);
        Test.stopTest();

        System.assertEquals(true, res.isSuccess(), 'Must succeed using default config name');
    }

    // ────────────────────────────────────────────────────
    // executeCallout — HTTP error paths
    // ────────────────────────────────────────────────────

    @isTest
    static void testExecuteCallout_HttpError_Parseable() {
        Order ord = [SELECT Id FROM Order WHERE SIAE_LocalName__c = :TEST_LOCAL_NAME LIMIT 1];
        OrderItem oi = [SELECT Id FROM OrderItem WHERE OrderId = :ord.Id LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new MockHttpError());

        Test.startTest();
        industriesintegrationfwk.IntegrationCalloutResponse res =
            SIAE_REST_CreateLocale.executeCallout('guid', oi.Id, '', null, null);
        Test.stopTest();

        System.assertEquals(false, res.isSuccess());
        System.assertEquals(400, res.getResponseCode());
        System.assert(res.getErrorMessage().contains('ERR001'), 'Error must contain code ERR001');
    }

    @isTest
    static void testExecuteCallout_HttpError_Unparseable() {
        Order ord = [SELECT Id FROM Order WHERE SIAE_LocalName__c = :TEST_LOCAL_NAME LIMIT 1];
        OrderItem oi = [SELECT Id FROM OrderItem WHERE OrderId = :ord.Id LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new MockUnparseableError());

        Test.startTest();
        industriesintegrationfwk.IntegrationCalloutResponse res =
            SIAE_REST_CreateLocale.executeCallout('guid', oi.Id, '', null, null);
        Test.stopTest();

        System.assertEquals(false, res.isSuccess());
        System.assertEquals(500, res.getResponseCode());
        System.assert(res.getErrorMessage().contains('HTTP 500'), 'Error must contain HTTP status');
    }

    // ────────────────────────────────────────────────────
    // buildRequestBody
    // ────────────────────────────────────────────────────

    @isTest
    static void testBuildRequestBody() {
        Order ord = [SELECT Id FROM Order WHERE SIAE_LocalName__c = :TEST_LOCAL_NAME LIMIT 1];

        Test.startTest();
        String body = SIAE_REST_CreateLocale.buildRequestBody(ord.Id);
        Test.stopTest();

        System.assertNotEquals(null, body, 'Body must not be null');
        System.assert(body.contains(TEST_LOCAL_NAME), 'Body must contain local name');
        System.assert(body.contains(TEST_EGON_CIV), 'Body must contain IdEgonCiv');
        System.assert(body.contains(TEST_SEPRAG), 'Body must contain Seprag');

        // locale.denominazione = nome locale, spazio.denominazione = 'Spazio <genere>'
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
        Map<String, Object> locale = (Map<String, Object>) parsed.get('locale');
        System.assertEquals(TEST_LOCAL_NAME, (String) locale.get('denominazione'),
            'locale.denominazione must stay the local name');

        List<Object> spazi = (List<Object>) locale.get('spazi');
        System.assertNotEquals(null, spazi, 'Body must contain spazi');
        System.assert(!spazi.isEmpty(), 'Body must contain at least 1 spazio');
        for (Object rawSpazio : spazi) {
            Map<String, Object> spazio = (Map<String, Object>) rawSpazio;
            System.assertEquals(EXPECTED_SPACE_NAME, (String) spazio.get('denominazione'),
                'spazio.denominazione must be "Spazio <genere>", not the local name');
        }
    }

    // ────────────────────────────────────────────────────
    // spazio.denominazione — 'Spazio <genere>'
    // ────────────────────────────────────────────────────

    @isTest
    static void testBuildRequest_SpaceNameFromGenere() {
        Order ord = loadOrderWithItems();

        Test.startTest();
        SIAE_REST_CreateLocale.CreateLocaleRequestDTO dto =
            SIAE_REST_CreateLocale.buildRequest(ord, new Map<Id, List<OrderItemAttribute>>());
        Test.stopTest();

        System.assertEquals(TEST_LOCAL_NAME, dto.locale.denominazione,
            'locale.denominazione must stay the local name');
        System.assertEquals(1, dto.locale.spazi.size(), 'Expected exactly 1 spazio');
        System.assertEquals(EXPECTED_SPACE_NAME, dto.locale.spazi[0].denominazione,
            'spazio.denominazione must be the fixed prefix + the row genere name');
    }

    @isTest
    static void testBuildSpaceName_PrefixPlusGenere() {
        Test.startTest();
        String spaceName = SIAE_REST_CreateLocale.buildSpaceName('Bar');
        Test.stopTest();

        System.assertEquals('Spazio Bar', spaceName,
            'Space name must be the fixed prefix + the genere name');
    }

    @isTest
    static void testBuildSpaceName_BlankGenereKeepsPrefixOnly() {
        Test.startTest();
        String fromBlankGenere = SIAE_REST_CreateLocale.buildSpaceName('   ');
        String fromNullGenere  = SIAE_REST_CreateLocale.buildSpaceName(null);
        Test.stopTest();

        System.assertEquals(EXPECTED_SPACE_PREFIX, fromBlankGenere,
            'Blank genere must yield the prefix alone');
        System.assertEquals(EXPECTED_SPACE_PREFIX, fromNullGenere,
            'Null genere must yield the prefix alone');
    }

    // Order + righe nella stessa forma della SOQL usata da executeCallout/buildRequestBody.
    private static Order loadOrderWithItems() {
        return [
            SELECT Id,
                   SIAE_LocalName__c,
                   SIAE_IdEgonCiv__c,
                   SIAE_Seprag__c,
                   (SELECT Id,
                           Product2Id,
                           Product2.ProductCode,
                           SIAE_GenereName__c
                    FROM OrderItems
                    ORDER BY CreatedDate ASC, Id ASC)
            FROM Order
            WHERE SIAE_LocalName__c = :TEST_LOCAL_NAME
            LIMIT 1
        ];
    }

    // ────────────────────────────────────────────────────
    // buildParametri — direct unit tests (@TestVisible)
    // ────────────────────────────────────────────────────

    @isTest
    static void testBuildParametri_NullMappings() {
        List<SIAE_REST_CreateLocale.ParametroDTO> result =
            SIAE_REST_CreateLocale.buildParametri(null, null);

        System.assertNotEquals(null, result);
        System.assertEquals(0, result.size());
    }

    @isTest
    static void testBuildParametri_EmptyMappings() {
        List<SIAE_REST_CreateLocale.ParametroDTO> result =
            SIAE_REST_CreateLocale.buildParametri(
                new List<OrderItemAttribute>(),
                new List<SIAE_GenereLocaleParameter__mdt>()
            );

        System.assertEquals(0, result.size());
    }

    @isTest
    static void testBuildParametri_OptionalMissing() {
        // Optional param → no attribute match → skipped silently
        SIAE_GenereLocaleParameter__mdt param = new SIAE_GenereLocaleParameter__mdt();
        param.SIAE_ParameterName__c = 'capienza';
        param.SIAE_AttributeDefinitionCode__c = 'SIAE-ATTR-QTA';
        param.SIAE_IsRequired__c = false;
        param.SIAE_DataType__c = null;

        List<SIAE_REST_CreateLocale.ParametroDTO> result =
            SIAE_REST_CreateLocale.buildParametri(
                null,
                new List<SIAE_GenereLocaleParameter__mdt>{ param }
            );

        System.assertEquals(0, result.size(), 'Optional param with no value must be skipped');
    }

    @isTest
    static void testBuildParametri_RequiredMissing_ThrowsException() {
        SIAE_GenereLocaleParameter__mdt param = new SIAE_GenereLocaleParameter__mdt();
        param.SIAE_ParameterName__c = 'capienza';
        param.SIAE_AttributeDefinitionCode__c = 'SIAE-ATTR-QTA';
        param.SIAE_IsRequired__c = true;
        param.SIAE_DataType__c = null;

        try {
            SIAE_REST_CreateLocale.buildParametri(
                null,
                new List<SIAE_GenereLocaleParameter__mdt>{ param }
            );
            System.assert(false, 'Expected IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('obbligatorio'), 'Error must mention "obbligatorio"');
            System.assert(e.getMessage().contains('capienza'), 'Error must mention param name');
        }
    }

    @isTest
    static void testBuildParametri_DefaultValue_NoAttribute() {
        // capienza v1.1: nessun attributo, valore fisso da SIAE_DefaultValue__c
        SIAE_GenereLocaleParameter__mdt param = new SIAE_GenereLocaleParameter__mdt();
        param.SIAE_ParameterName__c = 'Capienza';
        param.SIAE_AttributeDefinitionCode__c = null;
        param.SIAE_DefaultValue__c = '0';
        param.SIAE_IsRequired__c = false;

        List<SIAE_REST_CreateLocale.ParametroDTO> result =
            SIAE_REST_CreateLocale.buildParametri(
                null,
                new List<SIAE_GenereLocaleParameter__mdt>{ param }
            );

        System.assertEquals(1, result.size(), 'Default value must produce 1 parametro');
        System.assertEquals('Capienza', result[0].nome);
        System.assertEquals('0', result[0].valore);
    }

    @isTest
    static void testBuildParametri_DefaultValue_AttributeMissingValue() {
        // attributo configurato ma valore runtime assente -> fallback al default
        SIAE_GenereLocaleParameter__mdt param = new SIAE_GenereLocaleParameter__mdt();
        param.SIAE_ParameterName__c = 'Capienza';
        param.SIAE_AttributeDefinitionCode__c = 'SIAE-ATTR-QTA';
        param.SIAE_DefaultValue__c = '0';
        param.SIAE_IsRequired__c = false;

        List<SIAE_REST_CreateLocale.ParametroDTO> result =
            SIAE_REST_CreateLocale.buildParametri(
                null,
                new List<SIAE_GenereLocaleParameter__mdt>{ param }
            );

        System.assertEquals(1, result.size(), 'Missing runtime value must fallback to default');
        System.assertEquals('0', result[0].valore);
    }

    @isTest
    static void testBuildParametri_BlankAttributeCode_Skipped() {
        // Blank SIAE_AttributeDefinitionCode__c → entry skipped
        SIAE_GenereLocaleParameter__mdt param = new SIAE_GenereLocaleParameter__mdt();
        param.SIAE_ParameterName__c = 'someParam';
        param.SIAE_AttributeDefinitionCode__c = null;
        param.SIAE_IsRequired__c = false;

        List<SIAE_REST_CreateLocale.ParametroDTO> result =
            SIAE_REST_CreateLocale.buildParametri(
                null,
                new List<SIAE_GenereLocaleParameter__mdt>{ param }
            );

        System.assertEquals(0, result.size(), 'Blank code must skip entry');
    }

    @isTest
    static void testBuildParametri_UtilizzoNave_Optional_NoAttrs() {
        // utilizzoNave special case: both nav attrs missing, param optional → skipped
        SIAE_GenereLocaleParameter__mdt param = new SIAE_GenereLocaleParameter__mdt();
        param.SIAE_ParameterName__c = SIAE_UTIL_GenereLocaleConfig.PARAM_UTILIZZO_NAVE;
        param.SIAE_IsRequired__c = false;

        List<SIAE_REST_CreateLocale.ParametroDTO> result =
            SIAE_REST_CreateLocale.buildParametri(
                null,
                new List<SIAE_GenereLocaleParameter__mdt>{ param }
            );

        System.assertEquals(0, result.size(), 'Optional utilizzoNave with no attrs must be skipped');
    }

    @isTest
    static void testBuildParametri_UtilizzoNave_Required_ThrowsException() {
        SIAE_GenereLocaleParameter__mdt param = new SIAE_GenereLocaleParameter__mdt();
        param.SIAE_ParameterName__c = SIAE_UTIL_GenereLocaleConfig.PARAM_UTILIZZO_NAVE;
        param.SIAE_IsRequired__c = true;

        try {
            SIAE_REST_CreateLocale.buildParametri(
                null,
                new List<SIAE_GenereLocaleParameter__mdt>{ param }
            );
            System.assert(false, 'Expected IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('utilizzo'), 'Error must mention utilizzo');
        }
    }

    @isTest
    static void testBuildParametri_AttributeMatch_CoveredValue() {
        // JSON deserialize trick to populate AttributeDefinition relationship without DML
        SIAE_GenereLocaleParameter__mdt param = new SIAE_GenereLocaleParameter__mdt();
        param.SIAE_ParameterName__c = 'capienza';
        param.SIAE_AttributeDefinitionCode__c = 'SIAE-ATTR-QTA';
        param.SIAE_IsRequired__c = false;
        param.SIAE_DataType__c = null;

        String oiaJson = '[{"AttributeDefinition": {"Code": "SIAE-ATTR-QTA"}, "AttributeValue": "50"}]';
        List<OrderItemAttribute> attrs =
            (List<OrderItemAttribute>) JSON.deserialize(oiaJson, List<OrderItemAttribute>.class);

        List<SIAE_REST_CreateLocale.ParametroDTO> result =
            SIAE_REST_CreateLocale.buildParametri(
                attrs,
                new List<SIAE_GenereLocaleParameter__mdt>{ param }
            );

        System.assertEquals(1, result.size(), 'Must produce 1 parametro when attribute matches');
        System.assertEquals('capienza', result[0].nome);
        System.assertEquals('50', result[0].valore);
    }

    @isTest
    static void testBuildParametri_UtilizzoNave_Resolved() {
        // Both nav attributes present → resolveUtilizzoNave called
        SIAE_GenereLocaleParameter__mdt param = new SIAE_GenereLocaleParameter__mdt();
        param.SIAE_ParameterName__c = SIAE_UTIL_GenereLocaleConfig.PARAM_UTILIZZO_NAVE;
        param.SIAE_IsRequired__c = false;

        String oiaJson = '['
            + '{"AttributeDefinition": {"Code": "SIAE-ATTR-CLASS"}, "AttributeValue": "Nave adibita a navigazione interna da costiera"},'
            + '{"AttributeDefinition": {"Code": "SIAE-ATTR-QTA"}, "AttributeValue": "50"}'
            + ']';
        List<OrderItemAttribute> attrs =
            (List<OrderItemAttribute>) JSON.deserialize(oiaJson, List<OrderItemAttribute>.class);

        List<SIAE_REST_CreateLocale.ParametroDTO> result =
            SIAE_REST_CreateLocale.buildParametri(
                attrs,
                new List<SIAE_GenereLocaleParameter__mdt>{ param }
            );

        System.assertEquals(1, result.size(), 'Must produce utilizzoNave parametro');
        System.assertEquals(SIAE_UTIL_GenereLocaleConfig.PARAM_UTILIZZO_NAVE, result[0].nome);
        System.assertEquals('4', result[0].valore);
    }

    // ────────────────────────────────────────────────────
    // buildRequestBody — validation error paths
    // ────────────────────────────────────────────────────

    @isTest
    static void testBuildRequestBody_MissingLocalName() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Id pricebookId = Test.getStandardPricebookId();

        Order ord = new Order(
            AccountId        = acc.Id,
            EffectiveDate    = Date.today(),
            Status           = 'Draft',
            Pricebook2Id     = pricebookId,
            SIAE_IdEgonCiv__c = TEST_EGON_CIV
        );
        insert ord;

        Test.startTest();
        try {
            SIAE_REST_CreateLocale.buildRequestBody(ord.Id);
            System.assert(false, 'Expected IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('SIAE_LocalName__c'));
        }
        Test.stopTest();
    }

    @isTest
    static void testBuildRequestBody_MissingIdEgonCiv() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Id pricebookId = Test.getStandardPricebookId();

        Order ord = new Order(
            AccountId         = acc.Id,
            EffectiveDate     = Date.today(),
            Status            = 'Draft',
            Pricebook2Id      = pricebookId,
            SIAE_LocalName__c = TEST_LOCAL_NAME
        );
        insert ord;

        Test.startTest();
        try {
            SIAE_REST_CreateLocale.buildRequestBody(ord.Id);
            System.assert(false, 'Expected IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('SIAE_IdEgonCiv__c'));
        }
        Test.stopTest();
    }

    @isTest
    static void testBuildRequestBody_NoOrderItems() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Id pricebookId = Test.getStandardPricebookId();

        Order ord = new Order(
            AccountId         = acc.Id,
            EffectiveDate     = Date.today(),
            Status            = 'Draft',
            Pricebook2Id      = pricebookId,
            SIAE_LocalName__c = TEST_LOCAL_NAME,
            SIAE_IdEgonCiv__c = TEST_EGON_CIV,
            SIAE_Seprag__c    = TEST_SEPRAG
        );
        insert ord;

        Test.startTest();
        try {
            SIAE_REST_CreateLocale.buildRequestBody(ord.Id);
            System.assert(false, 'Expected IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('no OrderItems'));
        }
        Test.stopTest();
    }

    @isTest
    static void testBuildRequestBody_MissingSeprag() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Id pricebookId = Test.getStandardPricebookId();

        Order ord = new Order(
            AccountId         = acc.Id,
            EffectiveDate     = Date.today(),
            Status            = 'Draft',
            Pricebook2Id      = pricebookId,
            SIAE_LocalName__c = TEST_LOCAL_NAME,
            SIAE_IdEgonCiv__c = TEST_EGON_CIV
        );
        insert ord;

        Test.startTest();
        try {
            SIAE_REST_CreateLocale.buildRequestBody(ord.Id);
            System.assert(false, 'Expected IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('SIAE_Seprag__c'));
        }
        Test.stopTest();
    }

    // ────────────────────────────────────────────────────
    // HTTP Mock implementations
    // ────────────────────────────────────────────────────

    private class MockSuccess implements HttpCalloutMock {
        private String orderItemId;

        public MockSuccess(String orderItemId) {
            this.orderItemId = orderItemId;
        }

        public HttpResponse respond(HttpRequest req) {
            SIAE_REST_CreateLocale.SpazioResponseDTO spazioResp =
                new SIAE_REST_CreateLocale.SpazioResponseDTO();
            spazioResp.idSpazio       = TEST_SPAZIO_ID;
            spazioResp.denominazione  = TEST_LOCAL_NAME;
            spazioResp.idGenere       = '02';
            spazioResp.idRiferimento  = orderItemId;

            SIAE_REST_CreateLocale.CreateLocaleResponseDTO dto =
                new SIAE_REST_CreateLocale.CreateLocaleResponseDTO();
            dto.idLocale      = TEST_LOCALE_ID;
            dto.denominazione = TEST_LOCAL_NAME;
            dto.idGenere      = '02';
            dto.dataCreazione = '15/06/2026 10:00:00';
            dto.spazi         = new List<SIAE_REST_CreateLocale.SpazioResponseDTO>{ spazioResp };

            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(JSON.serialize(dto));
            return res;
        }
    }

    private class MockHttpError implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            SIAE_UTIL_IntegrationConfig.ErrorResponseDTO errDto =
                new SIAE_UTIL_IntegrationConfig.ErrorResponseDTO();
            errDto.code    = 'ERR001';
            errDto.message = 'Richiesta non valida';

            HttpResponse res = new HttpResponse();
            res.setStatusCode(400);
            res.setBody(JSON.serialize(errDto));
            return res;
        }
    }

    private class MockUnparseableError implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('Internal Server Error - Plain Text');
            return res;
        }
    }
}