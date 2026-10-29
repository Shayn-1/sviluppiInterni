/**
 * @description       : Test class for SIAE_REST_CreatePartnership
 * @author            : Iuliano Gaetano - gaetano.iuliano@nttdata.com
 * @group             : NTT Data
 * @last modified on  : 20/05/2026
 * @last modified by  : Iuliano Gaetano - gaetano.iuliano@nttdata.com
**/
@isTest
private class SIAE_REST_CreatePartnership_T {
    
    private static final String TEST_PARTNERSHIP_CODE = 'TEST01';
    private static final String TEST_IDCRM = '12345678';
    private static final Long TEST_OWNER_ID = 12345678L;
    private static final Long TEST_ASSOCIATION_ID = 98765432L;
    private static final String TEST_PARTNERSHIP_ID = 'PART-123456';
    
    /**
     * @description Setup test data
     */
    @testSetup
    static void setupData() {
        // Create Account with SIAE_IDCRM__c
        Account testAccount = new Account(
            Name = 'Test Account',
            SIAE_IDCRM__c = TEST_IDCRM
        );
        insert testAccount;
        
        // Get Standard PriceBook
        Id pricebookId = Test.getStandardPricebookId();
        
        // Create Product2
        Product2 testProduct = new Product2(
            Name = 'Test Product',
            IsActive = true
        );
        insert testProduct;
        
        // Create PricebookEntry
        PricebookEntry testPbe = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = testProduct.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert testPbe;
        
        // Create Order with Pricebook
        Order testOrder = new Order(
            AccountId = testAccount.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = pricebookId
        );
        insert testOrder;
        
        // Create OrderItem with required custom fields
        OrderItem testOrderItem = new OrderItem(
            OrderId = testOrder.Id,
            Product2Id = testProduct.Id,
            PricebookEntryId = testPbe.Id,
            Quantity = 1,
            UnitPrice = 100,
            SIAE_CommercialAgreementCode__c = TEST_PARTNERSHIP_CODE
        );
        insert testOrderItem;
    }
    
    /**
     * @description Test getProviderAttributes method
     */
    @isTest
    static void testGetProviderAttributes() {
        Test.startTest();
        List<industriesintegrationfwk.ApexProviderAttr> attributes = 
            SIAE_REST_CreatePartnership.getProviderAttributes();
        Test.stopTest();
        
        System.assertNotEquals(null, attributes, 'Attributes should not be null');
        System.assertEquals(1, attributes.size(), 'Should return exactly 1 attribute');
        System.assertNotEquals(null, attributes[0], 'Attribute should not be null');
    }
    
    /**
     * @description Test successful callout with business success
     */
    @isTest
    static void testExecuteCallout_Success() {
        OrderItem testItem = [SELECT Id FROM OrderItem LIMIT 1];
        
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseSuccess());
        
        Map<String, Object> attributes = new Map<String, Object>{
            'integrationConfigName' => 'CreatePartnership'
        };
        
        Test.startTest();
        industriesintegrationfwk.IntegrationCalloutResponse response = 
            SIAE_REST_CreatePartnership.executeCallout(
                'test-guid',
                testItem.Id,
                '',
                attributes,
                null
            );
        Test.stopTest();
        
        System.assertEquals(true, response.isSuccess(), 'Callout should be successful');
        System.assertEquals(200, response.getResponseCode(), 'Response code should be 200');
        
        // Verify OrderItem was updated
        OrderItem updatedItem = [
            SELECT SIAE_AssociationId__c, SIAE_PartnershipId__c 
            FROM OrderItem 
            WHERE Id = :testItem.Id
        ];
        System.assertEquals(String.valueOf(TEST_ASSOCIATION_ID), updatedItem.SIAE_AssociationId__c, 
            'AssociationId should be updated');
        System.assertEquals(TEST_PARTNERSHIP_ID, updatedItem.SIAE_PartnershipId__c, 
            'PartnershipId should be updated');
    }
    
    /**
     * @description Test callout with business failure (non-00 result code)
     */
    @isTest
    static void testExecuteCallout_BusinessFailure() {
        OrderItem testItem = [SELECT Id FROM OrderItem LIMIT 1];
        
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseBusinessFailure());
        
        Map<String, Object> attributes = new Map<String, Object>{
            'integrationConfigName' => 'CreatePartnership'
        };
        
        Test.startTest();
        industriesintegrationfwk.IntegrationCalloutResponse response = 
            SIAE_REST_CreatePartnership.executeCallout(
                'test-guid',
                testItem.Id,
                '',
                attributes,
                null
            );
        Test.stopTest();
        
        System.assertEquals(false, response.isSuccess(), 'Callout should fail due to business error');
        System.assertEquals(200, response.getResponseCode(), 'Response code should be 200');
        System.assert(response.getErrorMessage().contains('99'), 
            'Error message should contain error code');
        
        // Verify OrderItem was still updated with returned data
        OrderItem updatedItem = [
            SELECT SIAE_AssociationId__c, SIAE_PartnershipId__c 
            FROM OrderItem 
            WHERE Id = :testItem.Id
        ];
        System.assertEquals(String.valueOf(TEST_ASSOCIATION_ID), updatedItem.SIAE_AssociationId__c, 
            'AssociationId should be updated even on business failure');
    }
    
    /**
     * @description Test callout with status "I" (Inserted) and empty result: treated as success
     */
    @isTest
    static void testExecuteCallout_StatusInsertedTreatedAsSuccess() {
        OrderItem testItem = [SELECT Id FROM OrderItem LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new MockHttpResponseStatusInserted());

        Map<String, Object> attributes = new Map<String, Object>{
            'integrationConfigName' => 'CreatePartnership'
        };

        Test.startTest();
        industriesintegrationfwk.IntegrationCalloutResponse response =
            SIAE_REST_CreatePartnership.executeCallout(
                'test-guid',
                testItem.Id,
                '',
                attributes,
                null
            );
        Test.stopTest();

        System.assertEquals(true, response.isSuccess(),
            'Callout should be treated as successful when status is "I", even with empty result');
        System.assertEquals(200, response.getResponseCode(), 'Response code should be 200');

        // Verify OrderItem was still updated
        OrderItem updatedItem = [
            SELECT SIAE_AssociationId__c, SIAE_PartnershipId__c
            FROM OrderItem
            WHERE Id = :testItem.Id
        ];
        System.assertEquals(String.valueOf(TEST_ASSOCIATION_ID), updatedItem.SIAE_AssociationId__c,
            'AssociationId should be updated');
        System.assertEquals(TEST_PARTNERSHIP_ID, updatedItem.SIAE_PartnershipId__c,
            'PartnershipId should be updated');
    }

    /**
     * @description Test HTTP error response (non-200 status code)
     */
    @isTest
    static void testExecuteCallout_HttpError() {
        OrderItem testItem = [SELECT Id FROM OrderItem LIMIT 1];
        
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseError());
        
        Map<String, Object> attributes = new Map<String, Object>{
            'integrationConfigName' => 'CreatePartnership'
        };
        
        Test.startTest();
        industriesintegrationfwk.IntegrationCalloutResponse response = 
            SIAE_REST_CreatePartnership.executeCallout(
                'test-guid',
                testItem.Id,
                '',
                attributes,
                null
            );
        Test.stopTest();
        
        System.assertEquals(false, response.isSuccess(), 'Callout should fail');
        System.assertEquals(400, response.getResponseCode(), 'Response code should be 400');
        System.assert(response.getErrorMessage().contains('ERR001'), 
            'Error message should contain error code');
    }
    
    /**
     * @description Test with blank inputRecordId
     */
    @isTest
    static void testExecuteCallout_BlankInputRecordId() {
        Test.startTest();
        industriesintegrationfwk.IntegrationCalloutResponse response = 
            SIAE_REST_CreatePartnership.executeCallout(
                'test-guid',
                '',
                '',
                null,
                null
            );
        Test.stopTest();
        
        System.assertEquals(false, response.isSuccess(), 'Should fail with blank inputRecordId');
        System.assertEquals(500, response.getResponseCode(), 'Response code should be 500');
        System.assert(response.getErrorMessage().contains('inputRecordId is required'), 
            'Error message should mention inputRecordId');
    }
    
    /**
     * @description Test with null inputRecordId
     */
    @isTest
    static void testExecuteCallout_NullInputRecordId() {
        Test.startTest();
        industriesintegrationfwk.IntegrationCalloutResponse response = 
            SIAE_REST_CreatePartnership.executeCallout(
                'test-guid',
                null,
                '',
                null,
                null
            );
        Test.stopTest();
        
        System.assertEquals(false, response.isSuccess(), 'Should fail with null inputRecordId');
        System.assertEquals(500, response.getResponseCode(), 'Response code should be 500');
    }
    
    /**
     * @description Test with wrong SObject type (not OrderItem)
     */
    @isTest
    static void testExecuteCallout_WrongSObjectType() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        industriesintegrationfwk.IntegrationCalloutResponse response = 
            SIAE_REST_CreatePartnership.executeCallout(
                'test-guid',
                testAccount.Id,
                '',
                null,
                null
            );
        Test.stopTest();
        
        System.assertEquals(false, response.isSuccess(), 'Should fail with wrong SObject type');
        System.assertEquals(500, response.getResponseCode(), 'Response code should be 500');
        System.assert(response.getErrorMessage().contains('must be an OrderItem ID'), 
            'Error message should mention OrderItem');
    }
    
    /**
     * @description Test with missing SIAE_CommercialAgreementCode__c
     */
    @isTest
    static void testExecuteCallout_MissingPartnershipCode() {
        // Create OrderItem without partnership code
        Order testOrder = [SELECT Id FROM Order LIMIT 1];
        Product2 testProduct = [SELECT Id FROM Product2 LIMIT 1];
        PricebookEntry testPbe = [SELECT Id FROM PricebookEntry LIMIT 1];
        
        OrderItem itemWithoutCode = new OrderItem(
            OrderId = testOrder.Id,
            Product2Id = testProduct.Id,
            PricebookEntryId = testPbe.Id,
            Quantity = 1,
            UnitPrice = 100
        );
        insert itemWithoutCode;
        
        Test.startTest();
        industriesintegrationfwk.IntegrationCalloutResponse response = 
            SIAE_REST_CreatePartnership.executeCallout(
                'test-guid',
                itemWithoutCode.Id,
                '',
                null,
                null
            );
        Test.stopTest();
        
        System.assertEquals(true, response.isSuccess(), 'Blank partnership code should skip and succeed');
        System.assertEquals(200, response.getResponseCode(), 'Response code should be 200');
    }
    
    /**
     * @description Test with partnership code exceeding max length
     */
    @isTest
    static void testExecuteCallout_PartnershipCodeTooLong() {
        // Create OrderItem with code > 6 chars
        Order testOrder = [SELECT Id FROM Order LIMIT 1];
        Product2 testProduct = [SELECT Id FROM Product2 LIMIT 1];
        PricebookEntry testPbe = [SELECT Id FROM PricebookEntry LIMIT 1];
        
        OrderItem itemWithLongCode = new OrderItem(
            OrderId = testOrder.Id,
            Product2Id = testProduct.Id,
            PricebookEntryId = testPbe.Id,
            Quantity = 1,
            UnitPrice = 100,
            SIAE_CommercialAgreementCode__c = 'TOOLONG'  // 7 chars
        );
        insert itemWithLongCode;
        
        Test.startTest();
        industriesintegrationfwk.IntegrationCalloutResponse response = 
            SIAE_REST_CreatePartnership.executeCallout(
                'test-guid',
                itemWithLongCode.Id,
                '',
                null,
                null
            );
        Test.stopTest();
        
        System.assertEquals(false, response.isSuccess(), 'Should fail with code too long');
        System.assertEquals(500, response.getResponseCode(), 'Response code should be 500');
        System.assert(response.getErrorMessage().contains('exceeds max length'), 
            'Error message should mention max length');
    }
    
    /**
     * @description Test with missing Account SIAE_IDCRM__c
     */
    @isTest
    static void testExecuteCallout_MissingIDCRM() {
        // Create Account without IDCRM
        Account accountWithoutId = new Account(Name = 'Account Without IDCRM');
        insert accountWithoutId;
        
        // Get Standard PriceBook
        Id pricebookId = Test.getStandardPricebookId();
        
        Order orderWithoutIdCrm = new Order(
            AccountId = accountWithoutId.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = pricebookId
        );
        insert orderWithoutIdCrm;
        
        Product2 testProduct = [SELECT Id FROM Product2 LIMIT 1];
        PricebookEntry testPbe = [SELECT Id FROM PricebookEntry LIMIT 1];
        
        OrderItem itemWithoutIdCrm = new OrderItem(
            OrderId = orderWithoutIdCrm.Id,
            Product2Id = testProduct.Id,
            PricebookEntryId = testPbe.Id,
            Quantity = 1,
            UnitPrice = 100,
            SIAE_CommercialAgreementCode__c = TEST_PARTNERSHIP_CODE
        );
        insert itemWithoutIdCrm;
        
        Test.startTest();
        industriesintegrationfwk.IntegrationCalloutResponse response = 
            SIAE_REST_CreatePartnership.executeCallout(
                'test-guid',
                itemWithoutIdCrm.Id,
                '',
                null,
                null
            );
        Test.stopTest();
        
        System.assertEquals(false, response.isSuccess(), 'Should fail with missing IDCRM');
        System.assertEquals(500, response.getResponseCode(), 'Response code should be 500');
        System.assert(response.getErrorMessage().contains('Account.SIAE_IDCRM__c is required'), 
            'Error message should mention IDCRM field');
    }
    
    /**
     * @description Test with null attributes (should use default config name)
     */
    @isTest
    static void testExecuteCallout_NullAttributes() {
        OrderItem testItem = [SELECT Id FROM OrderItem LIMIT 1];
        
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseSuccess());
        
        Test.startTest();
        industriesintegrationfwk.IntegrationCalloutResponse response = 
            SIAE_REST_CreatePartnership.executeCallout(
                'test-guid',
                testItem.Id,
                '',
                null,
                null
            );
        Test.stopTest();
        
        System.assertEquals(true, response.isSuccess(), 'Should succeed with null attributes');
    }
    
    /**
     * @description Test HTTP error with unparseable error response
     */
    @isTest
    static void testExecuteCallout_UnparseableErrorResponse() {
        OrderItem testItem = [SELECT Id FROM OrderItem LIMIT 1];
        
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseUnparseableError());
        
        Map<String, Object> attributes = new Map<String, Object>{
            'integrationConfigName' => 'CreatePartnership'
        };
        
        Test.startTest();
        industriesintegrationfwk.IntegrationCalloutResponse response = 
            SIAE_REST_CreatePartnership.executeCallout(
                'test-guid',
                testItem.Id,
                '',
                attributes,
                null
            );
        Test.stopTest();
        
        System.assertEquals(false, response.isSuccess(), 'Should fail');
        System.assertEquals(500, response.getResponseCode(), 'Response code should be 500');
        System.assert(response.getErrorMessage().contains('HTTP 500'), 
            'Error message should contain HTTP status');
    }
    
    // ============================
    // HTTP Mock Implementations
    // ============================
    
    /**
     * @description Mock for successful HTTP response with business success
     */
    private class MockHttpResponseSuccess implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            
            SIAE_REST_CreatePartnership.ResponseDTO responseDto = 
                new SIAE_REST_CreatePartnership.ResponseDTO();
            responseDto.associationId = TEST_ASSOCIATION_ID;
            responseDto.ownerId = TEST_OWNER_ID;
            responseDto.status = 'SUCCESS';
            
            responseDto.partnership = new SIAE_REST_CreatePartnership.PartnershipDTO();
            responseDto.partnership.partnershipId = TEST_PARTNERSHIP_ID;
            responseDto.partnership.partnershipCode = TEST_PARTNERSHIP_CODE;
            
            responseDto.result = new SIAE_REST_CreatePartnership.ResultDTO();
            responseDto.result.code = '00';
            responseDto.result.description = 'Success';
            
            res.setBody(JSON.serialize(responseDto));
            return res;
        }
    }
    
    /**
     * @description Mock for HTTP 200 response with business failure (non-00 code)
     */
    private class MockHttpResponseBusinessFailure implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            
            SIAE_REST_CreatePartnership.ResponseDTO responseDto = 
                new SIAE_REST_CreatePartnership.ResponseDTO();
            responseDto.associationId = TEST_ASSOCIATION_ID;
            responseDto.ownerId = TEST_OWNER_ID;
            responseDto.status = 'FAILURE';
            
            responseDto.partnership = new SIAE_REST_CreatePartnership.PartnershipDTO();
            responseDto.partnership.partnershipId = TEST_PARTNERSHIP_ID;
            responseDto.partnership.partnershipCode = TEST_PARTNERSHIP_CODE;
            
            responseDto.result = new SIAE_REST_CreatePartnership.ResultDTO();
            responseDto.result.code = '99';
            responseDto.result.description = 'Business validation failed';
            
            res.setBody(JSON.serialize(responseDto));
            return res;
        }
    }
    
    /**
     * @description Mock for HTTP 200 response with status "I" and empty result (real-world case)
     */
    private class MockHttpResponseStatusInserted implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);

            SIAE_REST_CreatePartnership.ResponseDTO responseDto =
                new SIAE_REST_CreatePartnership.ResponseDTO();
            responseDto.associationId = TEST_ASSOCIATION_ID;
            responseDto.ownerId = TEST_OWNER_ID;
            responseDto.status = 'I';

            responseDto.partnership = new SIAE_REST_CreatePartnership.PartnershipDTO();
            responseDto.partnership.partnershipId = TEST_PARTNERSHIP_ID;
            responseDto.partnership.partnershipCode = TEST_PARTNERSHIP_CODE;

            responseDto.result = new SIAE_REST_CreatePartnership.ResultDTO();
            responseDto.result.code = null;
            responseDto.result.description = null;

            res.setBody(JSON.serialize(responseDto));
            return res;
        }
    }

    /**
     * @description Mock for HTTP error response (400)
     */
    private class MockHttpResponseError implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(400);
            
            SIAE_UTIL_IntegrationConfig.ErrorResponseDTO errorDto =
                new SIAE_UTIL_IntegrationConfig.ErrorResponseDTO();
            errorDto.code = 'ERR001';
            errorDto.message = 'Invalid request';
            
            res.setBody(JSON.serialize(errorDto));
            return res;
        }
    }
    
    /**
     * @description Mock for HTTP error with unparseable response
     */
    private class MockHttpResponseUnparseableError implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('Internal Server Error - Plain Text');
            return res;
        }
    }
}