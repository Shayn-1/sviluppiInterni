/**
 * @description       Test class for SIAE_REST_CompleteOrder + SIAE_REST_NotifyPaymentCallback
 * @author            Gaetano Iuliano - gaetano.iuliano@nttdata.com
 * @group             NTT Data — SIAE
 * @createdDate       2026-06-15
 * @lastModifiedDate  2026-07-07
 * @lastModifiedBy    Domenico Del Prete
 */
@isTest
private class SIAE_REST_CompleteOrder_T {

    private static final String TEST_IDCRM     = '1233454676';
    private static final String TEST_DDA_CARD  = '111111';
    private static final String TEST_DC_CARD   = '222222';
    private static final Long   TEST_PACCHETTO = 11336775255L;

    private static final String NOTIFY_RESP_JSON =
        '{"notificaMovimento_async":{"requestDTO":{'
        + '"headerType":{"codiceProcesso":"NTMO03","destinatario":"SUNSM","mittente":"SISTEMA INCASSI"},'
        + '"notificaMovimentoRequestDTO":{"anno":2026,"idMovimento":"100390573","importoMovimento":656.08}'
        + '}}}';

    @testSetup
    static void setupData() {
        Account acc = new Account(Name = 'Test Account CO', SIAE_IDCRM__c = TEST_IDCRM);
        insert acc;

        Id pricebookId = Test.getStandardPricebookId();

        Product2 prod = new Product2(Name = 'Prodotto CO Test', ProductCode = 'SIAE-PROD-FOYER', IsActive = true);
        insert prod;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = pricebookId, Product2Id = prod.Id, UnitPrice = 100, IsActive = true
        );
        insert pbe;

        Order ord = new Order(
            AccountId                 = acc.Id,
            EffectiveDate             = Date.today(),
            Status                    = 'Draft',
            Pricebook2Id              = pricebookId,
            SIAE_IncludeDC__c         = true,
            SIAE_NotifyPaymentResp__c = NOTIFY_RESP_JSON
        );
        insert ord;

        insert new OrderItem(
            OrderId          = ord.Id,
            Product2Id       = prod.Id,
            PricebookEntryId = pbe.Id,
            Quantity         = 1,
            UnitPrice        = 100,
            SIAE_DDACardId__c = TEST_DDA_CARD,
            SIAE_DCCardId__c  = TEST_DC_CARD
        );
    }

    // Id con prefisso FulfillmentStep (13W) valido ma inesistente: la SOQL su
    // FulfillmentStepDependency gira senza QueryException e ritorna vuoto.
    private static final String FAKE_STEP_ID = '13WMA000003Fsxe2AC';

    private static Order getOrder() {
        return [SELECT Id FROM Order LIMIT 1];
    }

    private static OrderItem getOrderItem() {
        return [SELECT Id, OrderId FROM OrderItem LIMIT 1];
    }

    // ── getProviderAttributes ────────────────────────────────────────────────

    @isTest
    static void testGetProviderAttributes() {
        Test.startTest();
        List<industriesintegrationfwk.ApexProviderAttr> attrs =
            SIAE_REST_CompleteOrder.getProviderAttributes();
        Test.stopTest();

        System.assertEquals(1, attrs.size(), 'Expected exactly 1 attribute');
    }

    // ── executeCallout — validation ──────────────────────────────────────────

    @isTest
    static void testExecuteCallout_BlankInputRecordId() {
        Test.startTest();
        industriesintegrationfwk.IntegrationCalloutResponse res =
            SIAE_REST_CompleteOrder.executeCallout('', '', '', null, null);
        Test.stopTest();

        System.assertEquals(false, res.isSuccess());
        System.assertEquals(500, res.getResponseCode());
        System.assert(res.getErrorMessage().contains('inputRecordId is required'));
    }

    @isTest
    static void testExecuteCallout_WrongSObjectType() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        industriesintegrationfwk.IntegrationCalloutResponse res =
            SIAE_REST_CompleteOrder.executeCallout('', acc.Id, '', null, null);
        Test.stopTest();

        System.assertEquals(false, res.isSuccess());
        System.assert(res.getErrorMessage().contains('must be an Order Item ID'));
    }

    // ── executeCallout — 202 success (copre query stepId + persist) ───────────

    @isTest
    static void testExecuteCallout_Accepted202() {
        Order ord = getOrder();
        OrderItem oi = getOrderItem();
        Test.setMock(HttpCalloutMock.class, new MockAccepted());

        Map<String, Object> attrs = new Map<String, Object>{ 'integrationConfigName' => 'CompleteOrder' };

        Test.startTest();
        industriesintegrationfwk.IntegrationCalloutResponse res =
            SIAE_REST_CompleteOrder.executeCallout('callout:' + FAKE_STEP_ID + ':', oi.Id, '', attrs, null);
        Test.stopTest();

        System.assertEquals(true, res.isSuccess(), 'Callout 202 must be treated as success');
        System.assertEquals(200, res.getResponseCode());

        Order updOrd = [SELECT SIAE_ReceiptPackageId__c FROM Order WHERE Id = :ord.Id];
        System.assertEquals(String.valueOf(TEST_PACCHETTO), updOrd.SIAE_ReceiptPackageId__c,
            'idPacchettoQuietanza must be persisted on Order');
    }

    @isTest
    static void testExecuteCallout_NullAttributes() {
        OrderItem oi = getOrderItem();
        Test.setMock(HttpCalloutMock.class, new MockAccepted());

        Test.startTest();
        industriesintegrationfwk.IntegrationCalloutResponse res =
            SIAE_REST_CompleteOrder.executeCallout('', oi.Id, '', null, null);
        Test.stopTest();

        System.assertEquals(true, res.isSuccess(), 'Must succeed using default config name');
    }

    // ── executeCallout — error paths ─────────────────────────────────────────

    @isTest
    static void testExecuteCallout_MissingIdCrmOrganizzatore() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        update new Account(Id = acc.Id, SIAE_IDCRM__c = null);

        Test.startTest();
        industriesintegrationfwk.IntegrationCalloutResponse res =
            SIAE_REST_CompleteOrder.executeCallout('', getOrderItem().Id, '', null, null);
        Test.stopTest();

        System.assertEquals(false, res.isSuccess());
        System.assertEquals(500, res.getResponseCode());
        System.assert(res.getErrorMessage().contains('idCrmOrganizzatore non risolto'),
            'Error must mention idCrmOrganizzatore');
    }

    @isTest
    static void testExecuteCallout_HttpError_Parseable() {
        OrderItem oi = getOrderItem();
        Test.setMock(HttpCalloutMock.class, new MockHttpError());

        Test.startTest();
        industriesintegrationfwk.IntegrationCalloutResponse res =
            SIAE_REST_CompleteOrder.executeCallout('', oi.Id, '', null, null);
        Test.stopTest();

        System.assertEquals(false, res.isSuccess());
        System.assertEquals(400, res.getResponseCode());
        System.assert(res.getErrorMessage().contains('ERR_004'));
    }

    @isTest
    static void testExecuteCallout_HttpError_Unparseable() {
        OrderItem oi = getOrderItem();
        Test.setMock(HttpCalloutMock.class, new MockUnparseableError());

        Test.startTest();
        industriesintegrationfwk.IntegrationCalloutResponse res =
            SIAE_REST_CompleteOrder.executeCallout('', oi.Id, '', null, null);
        Test.stopTest();

        System.assertEquals(false, res.isSuccess());
        System.assertEquals(500, res.getResponseCode());
        System.assert(res.getErrorMessage().contains('HTTP 500'));
    }

    @isTest
    static void testExecuteCallout_BlankNotifyResp() {
        Order ord = getOrder();
        update new Order(Id = ord.Id, SIAE_NotifyPaymentResp__c = '');

        Test.startTest();
        industriesintegrationfwk.IntegrationCalloutResponse res =
            SIAE_REST_CompleteOrder.executeCallout('', getOrderItem().Id, '', null, null);
        Test.stopTest();

        System.assertEquals(false, res.isSuccess());
        System.assertEquals(500, res.getResponseCode());
        System.assert(res.getErrorMessage().contains('SIAE_NotifyPaymentResp__c is blank'));
    }

    @isTest
    static void testExtractRequestDTO_Malformed() {
        Order ord = getOrder();
        update new Order(Id = ord.Id, SIAE_NotifyPaymentResp__c = '{not-json');

        Test.startTest();
        industriesintegrationfwk.IntegrationCalloutResponse res =
            SIAE_REST_CompleteOrder.executeCallout('', getOrderItem().Id, '', null, null);
        Test.stopTest();

        System.assertEquals(false, res.isSuccess());
        System.assert(res.getErrorMessage().contains('non è un JSON valido'));
    }

    @isTest
    static void testExtractRequestDTO_MissingNode() {
        Order ord = getOrder();
        update new Order(Id = ord.Id, SIAE_NotifyPaymentResp__c = '{"foo":"bar"}');

        Test.startTest();
        industriesintegrationfwk.IntegrationCalloutResponse res =
            SIAE_REST_CompleteOrder.executeCallout('', getOrderItem().Id, '', null, null);
        Test.stopTest();

        System.assertEquals(false, res.isSuccess());
        System.assert(res.getErrorMessage().contains('notificaMovimento_async'));
    }

    // ── buildRequestBody / build logic ───────────────────────────────────────

    @isTest
    static void testBuildRequestBody_IncludeDcTrue() {
        Order ord = getOrder();

        Test.startTest();
        String body = SIAE_REST_CompleteOrder.buildRequestBody(ord.Id);
        Test.stopTest();

        System.assert(body.contains('notificaMovimento_async'), 'Body must contain async node');
        System.assert(body.contains(TEST_IDCRM), 'Body must contain idCrmOrganizzatore');
        System.assert(body.contains(TEST_DDA_CARD), 'Body must contain DDA card');
        System.assert(body.contains(TEST_DC_CARD), 'Body must contain DC card when IncludeDC=true');
        System.assert(body.contains('SISTEMA INCASSI'), 'requestDTO must be embedded verbatim');
    }

    @isTest
    static void testBuildIdSchede_IncludeDcFalse() {
        Order ord = getOrder();
        update new Order(Id = ord.Id, SIAE_IncludeDC__c = false);

        Test.startTest();
        String body = SIAE_REST_CompleteOrder.buildRequestBody(ord.Id);
        Test.stopTest();

        System.assert(body.contains(TEST_DDA_CARD), 'DDA card always present');
        System.assert(!body.contains(TEST_DC_CARD), 'DC card must be excluded when IncludeDC=false');
    }

    @isTest
    static void testBuildIdSchede_Empty() {
        Order ord = getOrder();
        OrderItem oi = [SELECT Id FROM OrderItem WHERE OrderId = :ord.Id LIMIT 1];
        update new OrderItem(Id = oi.Id, SIAE_DDACardId__c = null, SIAE_DCCardId__c = null);

        Test.startTest();
        String body = SIAE_REST_CompleteOrder.buildRequestBody(ord.Id);
        Test.stopTest();

        System.assert(body.contains('"idSchede"'), 'idSchede key must be present');
        System.assert(!body.contains(TEST_DDA_CARD) && !body.contains(TEST_DC_CARD),
            'No card ids when both blank — empty array sent');
    }

    // buildRequest con stepId valorizzato: esercita la SOQL su
    // FulfillmentStepDependency; senza dependency lo stepId risolto è vuoto.
    @isTest
    static void testBuildRequest_StepIdResolvedFromDependency() {
        Order ord = [
            SELECT Id, Status, SIAE_IncludeDC__c, SIAE_NotifyPaymentResp__c,
                   Account.SIAE_IDCRM__c,
                   (SELECT Id, SIAE_DDACardId__c, SIAE_DCCardId__c FROM OrderItems)
            FROM Order WHERE Id = :getOrder().Id
        ];

        Test.startTest();
        SIAE_REST_CompleteOrder.CompleteOrderRequestDTO req =
            SIAE_REST_CompleteOrder.buildRequest(ord, 'callout:' + FAKE_STEP_ID + ':');
        Test.stopTest();

        System.assertEquals('', req.notificaMovimento_async.salesforce.stepId,
            'Senza FulfillmentStepDependency lo stepId risolto deve essere vuoto');
    }

    // ── extractStepId ────────────────────────────────────────────────────────

    @isTest
    static void testExtractStepId_Variants() {
        System.assertEquals('13WMA000003Fsxe2AC',
            SIAE_REST_CompleteOrder.extractStepId('callout:13WMA000003Fsxe2AC:'),
            'Must extract stepId from callout format');
        System.assertEquals(null, SIAE_REST_CompleteOrder.extractStepId(null));
        System.assertEquals('', SIAE_REST_CompleteOrder.extractStepId(''));
        System.assertEquals('13WMA000003Fsxe2AC',
            SIAE_REST_CompleteOrder.extractStepId('13WMA000003Fsxe2AC'),
            'Non-callout format returned as-is');
    }

    // ── Callback ─────────────────────────────────────────────────────────────

    @isTest
    static void testCallback_MissingFields() {
        RestContext.request  = restRequest('{"orderId":"","status":"","stepId":""}');
        RestContext.response = new RestResponse();

        Test.startTest();
        SIAE_REST_NotifyPaymentCallback.updateOrderStatus();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
        System.assert(RestContext.response.responseBody.toString().contains('obbligatori'));
    }

    @isTest
    static void testCallback_InvalidJson() {
        RestContext.request  = restRequest('{bad-json');
        RestResponse resp    = new RestResponse();
        RestContext.response = resp;

        Test.startTest();
        SIAE_REST_NotifyPaymentCallback.updateOrderStatus();
        Test.stopTest();

        System.assertEquals(400, resp.statusCode);
    }

    @isTest
    static void testCallback_DerivesStatus_RollbackOnBadStep() {
        Order ord = getOrder();
        RestContext.request  = restRequest(JSON.serialize(new Map<String, Object>{
            'orderId' => ord.Id, 'stepId' => 'badStepId' }));
        RestResponse resp    = new RestResponse();
        RestContext.response = resp;

        Test.startTest();
        SIAE_REST_NotifyPaymentCallback.updateOrderStatus();
        Test.stopTest();

        System.assertEquals(400, resp.statusCode);
        Order after = [SELECT Status FROM Order WHERE Id = :ord.Id];
        System.assertEquals('Draft', after.Status, 'Order non deve cambiare stato se lo step fallisce');
    }

    @isTest
    static void testCallback_InvalidId() {
        RestContext.request  = restRequest('{"orderId":"notAnId","status":"Fatturato","stepId":"alsoBad"}');
        RestResponse resp    = new RestResponse();
        RestContext.response = resp;

        Test.startTest();
        SIAE_REST_NotifyPaymentCallback.updateOrderStatus();
        Test.stopTest();

        System.assertEquals(400, resp.statusCode);
        System.assert(resp.responseBody.toString().contains('Id non valido'));
    }

    private static RestRequest restRequest(String body) {
        RestRequest req = new RestRequest();
        req.requestBody = Blob.valueOf(body);
        return req;
    }

    // ── HTTP Mocks ───────────────────────────────────────────────────────────

    private class MockAccepted implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            SIAE_REST_CompleteOrder.CompleteOrderResponseDTO dto =
                new SIAE_REST_CompleteOrder.CompleteOrderResponseDTO();
            dto.idPacchettoQuietanza = TEST_PACCHETTO;

            HttpResponse res = new HttpResponse();
            res.setStatusCode(202);
            res.setBody(JSON.serialize(dto));
            return res;
        }
    }

    private class MockHttpError implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            SIAE_UTIL_IntegrationConfig.ErrorResponseDTO errDto =
                new SIAE_UTIL_IntegrationConfig.ErrorResponseDTO();
            errDto.code    = 'ERR_004';
            errDto.message = 'Bad Input Parameters';

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