@IsTest
private class SIAE_REST_ConvertQuote_T {

    private static String buildPayload(
        String quoteId,
        String acceptanceDate,
        Boolean generalCondition,
        Boolean specialTerms,
        Boolean dataTruthfulness,
        Boolean consentGDPR,
        Boolean includeDC
    ) {
        SIAE_REST_ConvertQuote.ConvertQuoteRequest req =
            new SIAE_REST_ConvertQuote.ConvertQuoteRequest();

        req.quoteId = quoteId;
        req.acceptanceDate = acceptanceDate;
        req.generalCondition = generalCondition;
        req.specialTerms = specialTerms;
        req.dataTruthfulness = dataTruthfulness;
        req.consentGDPR = consentGDPR;
        req.includeDC = includeDC;

        return JSON.serialize(req);
    }

    private static RestResponse callRest(String payload) {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        req.requestUri = '/services/apexrest/SIAE/convertQuote/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(payload);

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        SIAE_REST_ConvertQuote.postConvertQuote();
        Test.stopTest();

        return RestContext.response;
    }

    private static Map<String, Object> responseAsMap(RestResponse res) {
        System.assertNotEquals(null, res, 'RestResponse non deve essere null.');
        System.assertNotEquals(null, res.responseBody, 'responseBody non deve essere null.');

        return (Map<String, Object>) JSON.deserializeUntyped(
            res.responseBody.toString()
        );
    }

    private static Account createAccount() {
        Account acc = new Account(
            Name = 'SIAE Convert Quote Test Account'
        );
        insert acc;
        return acc;
    }

    private static Opportunity createOpportunity(Id accountId) {
        Opportunity opp = new Opportunity(
            Name = 'SIAE Convert Quote Test Opportunity',
            AccountId = accountId,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;
        return opp;
    }

    private static Quote createQuoteForTest() {
        Account acc = createAccount();
        Opportunity opp = createOpportunity(acc.Id);

        Quote q = new Quote(
            Name = 'SIAE Convert Quote Test Quote',
            OpportunityId = opp.Id,
            Status = 'Draft',
            QuoteAccountId = acc.Id
        );
        insert q;

        return q;
    }

    private static Order createOrderForTest() {
        Account acc = createAccount();

        Order ord = new Order(
            AccountId = acc.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft'
        );
        insert ord;

        return ord;
    }

    private static void resetTestOrderId() {
        SIAE_REST_ConvertQuote.testOrderId = null;
        SIAE_REST_ConvertQuote.testForceBlankOrderId = false;
        SIAE_REST_ConvertQuote.testForceEmptyOrderQuery = false;
    }

    @IsTest
    static void executeConvertQuote_missingBody_throwsIllegalArgumentException() {
        Test.startTest();
        try {
            SIAE_REST_ConvertQuote.executeConvertQuote(null);
            System.assert(false, 'Era attesa IllegalArgumentException per body mancante.');
        } catch (IllegalArgumentException e) {
            System.assertEquals('Request body is mandatory.', e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void executeConvertQuote_missingQuoteId_throwsIllegalArgumentException() {
        String payload = buildPayload(
            null,
            String.valueOf(Date.today()),
            true,
            true,
            true,
            true,
            true
        );

        Test.startTest();
        try {
            SIAE_REST_ConvertQuote.executeConvertQuote(payload);
            System.assert(false, 'Era attesa IllegalArgumentException per quoteId mancante.');
        } catch (IllegalArgumentException e) {
            System.assertEquals('quoteId is mandatory.', e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void executeConvertQuote_quoteNotFound_throwsIllegalArgumentException() {
        String payload = buildPayload(
            '0Q0000000000000AAA',
            String.valueOf(Date.today()),
            true,
            true,
            true,
            true,
            true
        );

        Test.startTest();
        try {
            SIAE_REST_ConvertQuote.executeConvertQuote(payload);
            System.assert(false, 'Era attesa IllegalArgumentException per quoteId inesistente.');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('The quoteId field does not exist'));
        }
        Test.stopTest();
    }

    @IsTest
    static void executeConvertQuote_missingAcceptanceDate_throwsIllegalArgumentException() {
        Quote q = createQuoteForTest();

        String payload = buildPayload(
            q.Id,
            null,
            true,
            true,
            true,
            true,
            false
        );

        Test.startTest();
        try {
            SIAE_REST_ConvertQuote.executeConvertQuote(payload);
            System.assert(false, 'Era attesa IllegalArgumentException per acceptanceDate mancante.');
        } catch (IllegalArgumentException e) {
            System.assertEquals('acceptanceDate is mandatory.', e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void executeConvertQuote_invalidAcceptanceDate_throwsIllegalArgumentException() {
        Quote q = createQuoteForTest();

        String payload = buildPayload(
            q.Id,
            '28-05-2026',
            true,
            true,
            true,
            true,
            false
        );

        Test.startTest();
        try {
            SIAE_REST_ConvertQuote.executeConvertQuote(payload);
            System.assert(false, 'Era attesa IllegalArgumentException per acceptanceDate non valida.');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('acceptanceDate is not in valid format'));
        }
        Test.stopTest();
    }

    @IsTest
    static void executeConvertQuote_generalConditionFalse_throwsIllegalArgumentException() {
        Quote q = createQuoteForTest();

        String payload = buildPayload(
            q.Id,
            String.valueOf(Date.today()),
            false,
            true,
            true,
            true,
            true
        );

        Test.startTest();
        try {
            SIAE_REST_ConvertQuote.executeConvertQuote(payload);
            System.assert(false, 'Era attesa IllegalArgumentException per generalCondition false.');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('generalCondition'));
        }
        Test.stopTest();
    }

    @IsTest
    static void executeConvertQuote_specialTermsFalse_throwsIllegalArgumentException() {
        Quote q = createQuoteForTest();

        String payload = buildPayload(
            q.Id,
            String.valueOf(Date.today()),
            true,
            false,
            true,
            true,
            true
        );

        Test.startTest();
        try {
            SIAE_REST_ConvertQuote.executeConvertQuote(payload);
            System.assert(false, 'Era attesa IllegalArgumentException per specialTerms false.');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('specialTerms'));
        }
        Test.stopTest();
    }

    @IsTest
    static void executeConvertQuote_dataTruthfulnessFalse_throwsIllegalArgumentException() {
        Quote q = createQuoteForTest();

        String payload = buildPayload(
            q.Id,
            String.valueOf(Date.today()),
            true,
            true,
            false,
            true,
            true
        );

        Test.startTest();
        try {
            SIAE_REST_ConvertQuote.executeConvertQuote(payload);
            System.assert(false, 'Era attesa IllegalArgumentException per dataTruthfulness false.');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('dataTruthfulness'));
        }
        Test.stopTest();
    }

    @IsTest
    static void executeConvertQuote_consentGDPRNull_throwsIllegalArgumentException() {
        Quote q = createQuoteForTest();

        String payload = buildPayload(
            q.Id,
            String.valueOf(Date.today()),
            true,
            true,
            true,
            null,
            true
        );

        Test.startTest();
        try {
            SIAE_REST_ConvertQuote.executeConvertQuote(payload);
            System.assert(false, 'Era attesa IllegalArgumentException per consentGDPR null.');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('consentGDPR'));
        }
        Test.stopTest();
    }

    @IsTest
    static void executeConvertQuote_runningTestWithoutOrder_throwsFlowException() {
        resetTestOrderId();

        Quote q = createQuoteForTest();

        String payload = buildPayload(
            q.Id,
            String.valueOf(Date.today()),
            true,
            true,
            true,
            true,
            true
        );

        Test.startTest();
        try {
            SIAE_REST_ConvertQuote.executeConvertQuote(payload);
            System.assert(false, 'Era attesa FlowException per testOrderId mancante.');
        } catch (SIAE_REST_ConvertQuote.FlowException e) {
            System.assert(e.getMessage().contains('Internal error'));
        }
        Test.stopTest();

        resetTestOrderId();
    }

    @IsTest
    static void executeConvertQuote_success_updatesOrderFlags_withoutRunningFlow() {
        Quote q = createQuoteForTest();
        Order ord = createOrderForTest();

        SIAE_REST_ConvertQuote.testOrderId = ord.Id;

        String payload = buildPayload(
            q.Id,
            String.valueOf(Date.today()),
            true,
            true,
            true,
            true,
            true
        );

        Test.startTest();
        SIAE_REST_ConvertQuote.PostResponse result = SIAE_REST_ConvertQuote.executeConvertQuote(payload);
        Test.stopTest();

        resetTestOrderId();

        System.assertEquals(true, result.success);
        System.assertEquals(String.valueOf(ord.Id), result.orderId);

        Order updatedOrder = [
            SELECT Id,
                   SIAE_GeneralCondition__c,
                   SIAE_SpecialTerms__c,
                   SIAE_DataTruthfulness__c,
                   SIAE_ConsentGDPR__c,
                   SIAE_AcceptanceDate__c,
                   SIAE_IncludeDC__c
            FROM Order
            WHERE Id = :ord.Id
            LIMIT 1
        ];

        System.assertEquals(true, updatedOrder.SIAE_GeneralCondition__c);
        System.assertEquals(true, updatedOrder.SIAE_SpecialTerms__c);
        System.assertEquals(true, updatedOrder.SIAE_DataTruthfulness__c);
        System.assertEquals(true, updatedOrder.SIAE_ConsentGDPR__c);
        System.assertEquals(Date.today(), updatedOrder.SIAE_AcceptanceDate__c);
        System.assertEquals(true, updatedOrder.SIAE_IncludeDC__c);
    }

    @IsTest
    static void executeConvertQuote_blankOrderId_returnsUnsuccessfulResponse() {
        Quote q = createQuoteForTest();
        Order ord = createOrderForTest();

        SIAE_REST_ConvertQuote.testOrderId = ord.Id;
        SIAE_REST_ConvertQuote.testForceBlankOrderId = true;

        String payload = buildPayload(
            q.Id,
            String.valueOf(Date.today()),
            true,
            true,
            true,
            true,
            true
        );

        Test.startTest();
        SIAE_REST_ConvertQuote.PostResponse result = SIAE_REST_ConvertQuote.executeConvertQuote(payload);
        Test.stopTest();

        resetTestOrderId();

        System.assertEquals(false, result.success);
        System.assertEquals('', result.orderId);
        System.assertEquals('', result.referenceId);
    }

    @IsTest
    static void executeConvertQuote_emptyOrderQuery_returnsUnsuccessfulResponse() {
        Quote q = createQuoteForTest();
        Order ord = createOrderForTest();

        SIAE_REST_ConvertQuote.testOrderId = ord.Id;
        SIAE_REST_ConvertQuote.testForceEmptyOrderQuery = true;

        String payload = buildPayload(
            q.Id,
            String.valueOf(Date.today()),
            true,
            true,
            true,
            true,
            true
        );

        Test.startTest();
        SIAE_REST_ConvertQuote.PostResponse result = SIAE_REST_ConvertQuote.executeConvertQuote(payload);
        Test.stopTest();

        resetTestOrderId();

        System.assertEquals(false, result.success);
        System.assertEquals('', result.orderId);
        System.assertEquals('', result.referenceId);
    }

    @IsTest
    static void postConvertQuote_blankOrderId_returns500() {
        Quote q = createQuoteForTest();
        Order ord = createOrderForTest();

        SIAE_REST_ConvertQuote.testOrderId = ord.Id;
        SIAE_REST_ConvertQuote.testForceBlankOrderId = true;

        String payload = buildPayload(
            q.Id,
            String.valueOf(Date.today()),
            true,
            true,
            true,
            true,
            true
        );

        RestResponse res = callRest(payload);
        Map<String, Object> body = responseAsMap(res);

        resetTestOrderId();

        System.assertEquals(500, res.statusCode);
        System.assertEquals(false, (Boolean) body.get('success'));
        System.assertEquals(null, body.get('orderId'));
        System.assert(((String) body.get('errorMessage')).contains('Internal error'));
    }

    @IsTest
    static void postConvertQuote_missingQuoteId_returns400() {
        String payload = buildPayload(
            null,
            String.valueOf(Date.today()),
            true,
            true,
            true,
            true,
            true
        );

        RestResponse res = callRest(payload);
        Map<String, Object> body = responseAsMap(res);

        System.assertEquals(400, res.statusCode);
        System.assertEquals(false, (Boolean) body.get('success'));
        System.assertEquals(null, body.get('orderId'));
        System.assertEquals('quoteId is mandatory.', (String) body.get('errorMessage'));
    }

    @IsTest
    static void postConvertQuote_invalidDate_returns400() {
        Quote q = createQuoteForTest();

        String payload = buildPayload(
            q.Id,
            '2026/05/28',
            true,
            true,
            true,
            true,
            true
        );

        RestResponse res = callRest(payload);
        Map<String, Object> body = responseAsMap(res);

        System.assertEquals(400, res.statusCode);
        System.assertEquals(false, (Boolean) body.get('success'));
        System.assert(((String) body.get('errorMessage')).contains('acceptanceDate is not in valid format'));
    }

    @IsTest
    static void postConvertQuote_flagNotAccepted_returns400() {
        Quote q = createQuoteForTest();

        String payload = buildPayload(
            q.Id,
            String.valueOf(Date.today()),
            true,
            true,
            true,
            false,
            false
        );

        RestResponse res = callRest(payload);
        Map<String, Object> body = responseAsMap(res);

        System.assertEquals(400, res.statusCode);
        System.assertEquals(false, (Boolean) body.get('success'));
        System.assertEquals(null, body.get('orderId'));
        System.assert(((String) body.get('errorMessage')).contains('consentGDPR'));
    }

    @IsTest
    static void postConvertQuote_runningTestWithoutOrder_returns500() {
        resetTestOrderId();

        Quote q = createQuoteForTest();

        String payload = buildPayload(
            q.Id,
            String.valueOf(Date.today()),
            true,
            true,
            true,
            true,
            true
        );

        RestResponse res = callRest(payload);
        Map<String, Object> body = responseAsMap(res);

        resetTestOrderId();

        System.assertEquals(500, res.statusCode);
        System.assertEquals(false, (Boolean) body.get('success'));
        System.assertEquals(null, body.get('orderId'));
        System.assert(((String) body.get('errorMessage')).contains('Internal error'));
    }

    @IsTest
    static void postConvertQuote_success_returns200Payload_withoutRunningFlow() {
        Quote q = createQuoteForTest();
        Order ord = createOrderForTest();

        SIAE_REST_ConvertQuote.testOrderId = ord.Id;

        String payload = buildPayload(
            q.Id,
            String.valueOf(Date.today()),
            true,
            true,
            true,
            true,
            false
        );

        RestResponse res = callRest(payload);
        Map<String, Object> body = responseAsMap(res);

        resetTestOrderId();

        System.assertEquals(true, (Boolean) body.get('success'));
        System.assertEquals(String.valueOf(ord.Id), (String) body.get('orderId'));
        System.assertEquals('', (String) body.get('errorMessage'));

        Order updatedOrder = [
            SELECT Id,
                   SIAE_IncludeDC__c,
                   SIAE_AcceptanceDate__c
            FROM Order
            WHERE Id = :ord.Id
            LIMIT 1
        ];

        System.assertEquals(false, updatedOrder.SIAE_IncludeDC__c);
        System.assertEquals(Date.today(), updatedOrder.SIAE_AcceptanceDate__c);
    }
}