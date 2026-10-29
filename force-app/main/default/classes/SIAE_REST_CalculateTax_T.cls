/**
 * @description Test per SIAE_REST_CalculateTax (callout SAP/Mulesoft per il calcolo tasse).
 */
@IsTest
private class SIAE_REST_CalculateTax_T {

    private class Mock implements HttpCalloutMock {
        Integer statusCode;
        String body;
        Mock(Integer statusCode, String body) { this.statusCode = statusCode; this.body = body; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(statusCode);
            res.setBody(body);
            return res;
        }
    }

    private static SIAE_REST_CalculateTax.Request buildRequest() {
        SIAE_REST_CalculateTax.Request req = new SIAE_REST_CalculateTax.Request();
        req.idSap = '9027071900';
        req.seprag = '0906806';
        req.idCarrello = '0Q0000000000001AAA';

        SIAE_REST_CalculateTax.QuoteLineItemRequest line = new SIAE_REST_CalculateTax.QuoteLineItemRequest();
        line.id = '0QL000000000001AAA';
        line.totaleDda = '486.20';
        line.totaleDc = '3.00';
        SIAE_REST_CalculateTax.VoceCosto voce = new SIAE_REST_CalculateTax.VoceCosto();
        voce.voceIncasso = '2272'; voce.quantita = '1'; voce.importo = '486.20';
        line.vociCostoDda.add(voce);
        req.quoteLineItem.add(line);
        return req;
    }

    private static String successBody(String lineId) {
        SIAE_REST_CalculateTax.Response resp = new SIAE_REST_CalculateTax.Response();
        resp.idCarrello = '0Q0000000000001AAA';
        SIAE_REST_CalculateTax.QuoteLineItemResponse r = new SIAE_REST_CalculateTax.QuoteLineItemResponse();
        r.id = lineId;
        r.importoImposteDda = '10.00'; r.importoImposteDc = '2.00';
        r.importoBolloDda = '2.00'; r.importoBolloDc = '1.00';
        SIAE_REST_CalculateTax.QuoteLineItemWrapper wrapper = new SIAE_REST_CalculateTax.QuoteLineItemWrapper();
        wrapper.payload = r;
        resp.quoteLineItem = new List<SIAE_REST_CalculateTax.QuoteLineItemWrapper>{ wrapper };
        return JSON.serialize(resp);
    }

    @IsTest
    static void shouldReturnTaxes_OnSuccess() {
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new Mock(200, successBody('0QL000000000001AAA')));
        SIAE_REST_CalculateTax.CalculateTaxResult result = SIAE_REST_CalculateTax.calculate(buildRequest());
        Test.stopTest();

        System.assertEquals(true, result.success, 'Callout 200 → success.');
        System.assertEquals(200, result.statusCode);
        System.assertEquals(1, result.taxByLineId.size(), 'Una riga mappata.');
        SIAE_REST_CalculateTax.QuoteLineItemResponse line =
            result.taxByLineId.get('0QL000000000001AAA'.left(15));
        System.assertNotEquals(null, line, 'Match per id riga (15 char).');
        System.assertEquals('10.00', line.importoImposteDda);
    }

    @IsTest
    static void shouldReturnError_OnNon2xx() {
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new Mock(500, '{"code":"500","message":"SAP down"}'));
        SIAE_REST_CalculateTax.CalculateTaxResult result = SIAE_REST_CalculateTax.calculate(buildRequest());
        Test.stopTest();

        System.assertEquals(false, result.success, 'HTTP 500 → failure.');
        System.assertEquals(500, result.statusCode);
        System.assert(String.isNotBlank(result.errorMessage), 'Deve esserci un messaggio di errore.');
    }

    @IsTest
    static void shouldReturnEarly_WhenRequestNullOrEmpty() {
        Test.startTest();
        SIAE_REST_CalculateTax.CalculateTaxResult nullResult = SIAE_REST_CalculateTax.calculate(null);
        SIAE_REST_CalculateTax.Request emptyReq = new SIAE_REST_CalculateTax.Request();
        SIAE_REST_CalculateTax.CalculateTaxResult emptyResult = SIAE_REST_CalculateTax.calculate(emptyReq);
        Test.stopTest();

        System.assertEquals(true, nullResult.success, 'Request null → success senza callout.');
        System.assertEquals(true, emptyResult.success, 'Nessuna riga → success senza callout.');
        System.assert(nullResult.taxByLineId.isEmpty());
    }

    @IsTest
    static void shouldHandleException_OnInvalidResponseBody() {
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new Mock(200, '{not valid json'));
        SIAE_REST_CalculateTax.CalculateTaxResult result = SIAE_REST_CalculateTax.calculate(buildRequest());
        Test.stopTest();

        System.assertEquals(false, result.success, 'Body non parsabile → failure gestita.');
        System.assert(String.isNotBlank(result.errorMessage), 'Messaggio di errore valorizzato.');
    }
}