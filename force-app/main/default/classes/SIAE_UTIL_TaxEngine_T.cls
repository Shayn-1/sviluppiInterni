/**
 * @description Test per SIAE_UTIL_TaxEngine (TaxAdapter RLM) dopo la migrazione del calcolo
 *              tasse verso SAP (servizio Fatt14) tramite SIAE_REST_CalculateTax.
 *              Il calcolo del contesto Quote esegue un callout sincrono: viene usato un HttpCalloutMock
 *              che rimanda gli id riga inviati con importi fissi.
 */
@IsTest
private class SIAE_UTIL_TaxEngine_T {

    @TestSetup
    static void setupTestData() {
        Account acc = SIAE_TestDataFactory.createAccount(false);
        acc.SIAE_TaxClassification__c = 'IT_STANDARD';
        acc.SIAE_IDSap__c = '9027071900';
        insert acc;

        List<Product2> products = SIAE_TestDataFactory.createProducts(3, true);

        Id standardPricebookId = Test.getStandardPricebookId();
        List<PricebookEntry> pbes = SIAE_TestDataFactory.createPricebookEntries(
            products, standardPricebookId, true
        );

        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity Tax Engine',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Pricebook2Id = standardPricebookId
        );
        insert opp;

        Quote quote = SIAE_TestDataFactory.createQuote(opp, false);
        quote.QuoteAccountId = acc.Id;
        quote.Pricebook2Id = standardPricebookId;
        quote.SIAE_Seprag__c = '0906806';
        insert quote;

        List<QuoteLineItem> qlis = new List<QuoteLineItem>();
        for (Integer i = 0; i < 3; i++) {
            qlis.add(new QuoteLineItem(
                QuoteId = quote.Id,
                PricebookEntryId = pbes[i].Id,
                Product2Id = products[i].Id,
                Quantity = 1 + i,
                UnitPrice = 100.00,
                SIAE_PaymentItems__c = buildPaymentItemsJson(i),
                SIAE_TotalDA__c = 486.20,
                SIAE_DirittiConnessi__c = 3.00
            ));
        }
        insert qlis;

        Order ord = SIAE_TestDataFactory.createOrder(acc, false);
        ord.Pricebook2Id = standardPricebookId;
        ord.Status = 'Draft';
        ord.EffectiveDate = Date.today();
        insert ord;

        List<OrderItem> ois = new List<OrderItem>();
        for (Integer i = 0; i < 3; i++) {
            ois.add(new OrderItem(
                OrderId = ord.Id,
                PricebookEntryId = pbes[i].Id,
                Product2Id = products[i].Id,
                Quantity = 1 + i,
                UnitPrice = 100.00,
                SIAE_PaymentItems__c = buildPaymentItemsJson(i),
                SIAE_TotalDA__c = 486.20,
                SIAE_DirittiConnessi__c = 3.00
            ));
        }
        insert ois;
    }

    private static String buildPaymentItemsJson(Integer index) {
        return '{"paymentItems": [' +
            '{"itemCode": "DDA' + index + '", "amount": "486.20", "type": "DDA", "materialTaxClassification": "E"},' +
            '{"itemCode": "SIDDA' + index + '", "amount": "3.00", "type": "SI_DDA", "materialTaxClassification": ""},' +
            '{"itemCode": "DC' + index + '", "amount": "20.00", "type": "DC", "materialTaxClassification": ""},' +
            '{"itemCode": "SIDC' + index + '", "amount": "1.00", "type": "SI_DC", "materialTaxClassification": ""},' +
            '{"itemCode": "QA' + index + '", "amount": "50.00", "type": "QA", "materialTaxClassification": ""}' +
            ']}';
    }

    // ─── HttpCalloutMock: rimanda gli id ricevuti con importi fissi ───
    private class TaxMock implements HttpCalloutMock {
        public Integer statusCode = 200;
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(statusCode);
            if (statusCode != 200) {
                res.setBody('{"code":"500","message":"SAP error"}');
                return res;
            }
            SIAE_REST_CalculateTax.Request parsed =
                (SIAE_REST_CalculateTax.Request) JSON.deserialize(req.getBody(), SIAE_REST_CalculateTax.Request.class);
            SIAE_REST_CalculateTax.Response resp = new SIAE_REST_CalculateTax.Response();
            resp.idCarrello = parsed.idCarrello;
            resp.quoteLineItem = new List<SIAE_REST_CalculateTax.QuoteLineItemWrapper>();
            if (parsed.quoteLineItem != null) {
                for (SIAE_REST_CalculateTax.QuoteLineItemRequest q : parsed.quoteLineItem) {
                    SIAE_REST_CalculateTax.QuoteLineItemResponse r =
                        new SIAE_REST_CalculateTax.QuoteLineItemResponse();
                    r.id = q.id;
                    r.importoImposteDda = '10.00';
                    r.importoImposteDc  = '2.00';
                    r.importoBolloDda   = '2.00';
                    r.importoBolloDc    = '1.00';
                    SIAE_REST_CalculateTax.QuoteLineItemWrapper w =
                        new SIAE_REST_CalculateTax.QuoteLineItemWrapper();
                    w.payload = r;
                    resp.quoteLineItem.add(w);
                }
            }
            res.setBody(JSON.serialize(resp));
            return res;
        }
    }

    private static SIAE_UTIL_TaxEngine.TaxCalculationInput buildCoreInput(
        String referenceEntityId,
        SIAE_UTIL_TaxEngine.ContextType contextType,
        List<String> lineIds
    ) {
        SIAE_UTIL_TaxEngine.TaxCalculationInput input =
            new SIAE_UTIL_TaxEngine.TaxCalculationInput();
        input.referenceEntityId = referenceEntityId;
        input.contextType = contextType;
        input.documentCode = 'DOC-TEST';
        input.referenceDocumentCode = 'REF-DOC-TEST';
        input.currencyIsoCode = 'EUR';
        input.transactionDate = System.now();
        input.isCommit = false;
        for (String lineId : lineIds) {
            SIAE_UTIL_TaxEngine.TaxCalculationLineInput line =
                new SIAE_UTIL_TaxEngine.TaxCalculationLineInput();
            line.lineNumber = lineId;
            line.amount = 100;
            line.taxCode = 'SIAE';
            line.productCode = 'TEST';
            line.quantity = 1;
            input.lines.add(line);
        }
        return input;
    }

    @IsTest
    static void shouldCalculateTaxCore_WhenQuoteContext() {
        Quote quote = [SELECT Id FROM Quote LIMIT 1];
        List<QuoteLineItem> qlis = [SELECT Id FROM QuoteLineItem ORDER BY CreatedDate ASC LIMIT 3];

        List<String> lineIds = new List<String>();
        for (QuoteLineItem qli : qlis) { lineIds.add(String.valueOf(qli.Id)); }

        SIAE_UTIL_TaxEngine engine = new SIAE_UTIL_TaxEngine();
        SIAE_UTIL_TaxEngine.TaxCalculationInput input =
            buildCoreInput(quote.Id, SIAE_UTIL_TaxEngine.ContextType.QUOTE, lineIds);

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new TaxMock());
        SIAE_UTIL_TaxEngine.TaxCalculationOutput output = engine.calculateTaxCore(input);
        Test.stopTest();

        System.assertEquals(3, output.calcResultByLineId.size(), 'Tutte le righe Quote devono essere calcolate.');
        System.assertEquals(300, output.grandTotalAmount, 'Il totale imponibile input somma gli amount.');

        for (QuoteLineItem qli : qlis) {
            String lineId15 = String.valueOf(qli.Id).left(15);
            SIAE_UTIL_TaxEngine.TaxCalcResult result = output.calcResultByLineId.get(lineId15);
            System.assertNotEquals(null, result, 'Risultato mancante per ' + lineId15);
            System.assertEquals(10.00, result.totalTaxDA, 'Imposte DDA da SAP.');
            System.assertEquals(2.00, result.totalTaxDC, 'Imposte DC da SAP.');
            System.assertEquals(2.00, result.totalTaxBolloDDA, 'Bollo DDA da SAP.');
            System.assertEquals(1.00, result.totalTaxBolloDC, 'Bollo DC da SAP.');
            System.assertEquals(15.00, result.totalTax, 'Totale = DA+DC+BolloDDA+BolloDC.');
        }
        System.assertEquals(45.00, output.grandTotalTax, 'Totale tasse = 3 righe x 15.');
    }

    @IsTest
    static void shouldReceiveSapData_WhenOrderContext() {
        Order ord = [SELECT Id FROM Order LIMIT 1];
        List<OrderItem> ois = [SELECT Id FROM OrderItem ORDER BY CreatedDate ASC LIMIT 3];
        List<String> lineIds = new List<String>();
        for (OrderItem oi : ois) { lineIds.add(String.valueOf(oi.Id)); }

        SIAE_UTIL_TaxEngine engine = new SIAE_UTIL_TaxEngine();
        SIAE_UTIL_TaxEngine.TaxCalculationInput input =
            buildCoreInput(ord.Id, SIAE_UTIL_TaxEngine.ContextType.ORDER, lineIds);

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new TaxMock());
        SIAE_UTIL_TaxEngine.TaxCalculationOutput output = engine.calculateTaxCore(input);
        Test.stopTest();

        System.assertEquals(3, output.calcResultByLineId.size(), 'Contesto Order: 3 righe nel risultato.');
        for (OrderItem oi : ois) {
            String lineId15 = String.valueOf(oi.Id).left(15);
            SIAE_UTIL_TaxEngine.TaxCalcResult res = output.calcResultByLineId.get(lineId15);
            System.assertNotEquals(null, res, 'Risultato presente per ogni OI.');
            System.assertEquals(true,  res.sapDataReceived, 'SAP ha risposto per contesto Order.');
            System.assertEquals(10.00, res.totalTaxDA,      'DA ricevuto da SAP (Order).');
            System.assertEquals(2.00,  res.totalTaxDC,      'DC ricevuto da SAP (Order).');
        }
    }

    @IsTest
    static void shouldDetectContext_WhenContextTypeNull() {
        Quote quote = [SELECT Id FROM Quote LIMIT 1];
        QuoteLineItem qli = [SELECT Id FROM QuoteLineItem LIMIT 1];

        SIAE_UTIL_TaxEngine engine = new SIAE_UTIL_TaxEngine();
        SIAE_UTIL_TaxEngine.TaxCalculationInput input =
            buildCoreInput(quote.Id, null, new List<String>{ String.valueOf(qli.Id) });

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new TaxMock());
        SIAE_UTIL_TaxEngine.TaxCalculationOutput output = engine.calculateTaxCore(input);
        Test.stopTest();

        System.assertEquals(1, output.calcResultByLineId.size(), 'Il context deve essere rilevato dal referenceEntityId.');
    }

    @IsTest
    static void shouldReturnEmpty_WhenInputNullOrEmpty() {
        SIAE_UTIL_TaxEngine engine = new SIAE_UTIL_TaxEngine();
        Test.startTest();
        SIAE_UTIL_TaxEngine.TaxCalculationOutput nullOutput = engine.calculateTaxCore(null);
        SIAE_UTIL_TaxEngine.TaxCalculationOutput emptyOutput =
            engine.calculateTaxCore(new SIAE_UTIL_TaxEngine.TaxCalculationInput());
        Test.stopTest();
        System.assertEquals(0, nullOutput.calcResultByLineId.size(), 'Input null → output vuoto.');
        System.assertEquals(0, emptyOutput.calcResultByLineId.size(), 'Input senza righe → output vuoto.');
    }

    @IsTest
    static void shouldReturnEmpty_WhenLinesHaveNoLineNumber() {
        Quote quote = [SELECT Id FROM Quote LIMIT 1];
        SIAE_UTIL_TaxEngine.TaxCalculationInput input =
            new SIAE_UTIL_TaxEngine.TaxCalculationInput();
        input.referenceEntityId = quote.Id;
        input.contextType = SIAE_UTIL_TaxEngine.ContextType.QUOTE;
        SIAE_UTIL_TaxEngine.TaxCalculationLineInput line =
            new SIAE_UTIL_TaxEngine.TaxCalculationLineInput();
        line.lineNumber = null;
        line.amount = 100;
        input.lines.add(line);

        SIAE_UTIL_TaxEngine engine = new SIAE_UTIL_TaxEngine();
        Test.startTest();
        SIAE_UTIL_TaxEngine.TaxCalculationOutput output = engine.calculateTaxCore(input);
        Test.stopTest();
        System.assertEquals(0, output.calcResultByLineId.size(), 'Righe senza lineNumber non elaborate.');
    }

    @IsTest
    static void shouldBuildSapRequest_SplittingVociByType() {
        Quote quote = [SELECT Id FROM Quote LIMIT 1];
        List<QuoteLineItem> qlis = [SELECT Id FROM QuoteLineItem ORDER BY CreatedDate ASC LIMIT 1];

        SIAE_UTIL_TaxEngine engine = new SIAE_UTIL_TaxEngine();
        Set<String> ids = new Set<String>{ String.valueOf(qlis[0].Id).left(15) };

        Test.startTest();
        Map<String, SIAE_UTIL_TaxEngine.QuoteLineData> dataByLine = engine.queryQuoteLineData(ids);
        SIAE_UTIL_TaxEngine.QuoteHeader header = engine.resolveQuoteHeader(quote.Id);

        List<String> lineIds = new List<String>{ String.valueOf(qlis[0].Id) };
        SIAE_UTIL_TaxEngine.TaxCalculationInput input =
            buildCoreInput(quote.Id, SIAE_UTIL_TaxEngine.ContextType.QUOTE, lineIds);

        SIAE_REST_CalculateTax.Request req = engine.buildSapRequest(header, input.lines, dataByLine);
        Test.stopTest();

        System.assertEquals('9027071900', req.idSap, 'idSap da QuoteAccount.SIAE_IDSap__c.');
        System.assertEquals('0906806', req.seprag, 'seprag da Quote.SIAE_Seprag__c.');
        System.assertEquals(quote.Id, req.idCarrello, 'idCarrello = Quote.Id.');
        System.assertEquals(false, req.flagNoBollo, 'flagNoBollo default false.');
        System.assertEquals(1, req.quoteLineItem.size(), 'Una riga.');
        SIAE_REST_CalculateTax.QuoteLineItemRequest line = req.quoteLineItem[0];
        System.assertEquals(2, line.vociCostoDda.size(), 'DDA + SI_DDA nel bucket DDA.');
        System.assertEquals(2, line.vociCostoDc.size(), 'DC + SI_DC nel bucket DC.');
        System.assertEquals('486.20', line.totaleDda, 'totaleDda da SIAE_TotalDA__c.');
        System.assertEquals('3.00', line.totaleDc, 'totaleDc da SIAE_DirittiConnessi__c.');
        System.assertEquals('1', line.vociCostoDda[0].quantita, 'quantita default "1".');
    }

    @IsTest
    static void shouldQueryQuoteLineData() {
        List<QuoteLineItem> qlis = [SELECT Id FROM QuoteLineItem];
        Set<String> ids = new Set<String>();
        for (QuoteLineItem qli : qlis) { ids.add(String.valueOf(qli.Id).left(15)); }

        SIAE_UTIL_TaxEngine engine = new SIAE_UTIL_TaxEngine();
        Test.startTest();
        Map<String, SIAE_UTIL_TaxEngine.QuoteLineData> data = engine.queryQuoteLineData(ids);
        Map<String, SIAE_UTIL_TaxEngine.QuoteLineData> empty = engine.queryQuoteLineData(new Set<String>());
        Test.stopTest();

        System.assertEquals(3, data.size(), '3 righe.');
        System.assert(empty.isEmpty(), 'Set vuoto → mappa vuota.');
    }

    @IsTest
    static void shouldResolveQuoteHeader_AndThrowOnErrors() {
        Quote quote = [SELECT Id FROM Quote LIMIT 1];
        SIAE_UTIL_TaxEngine engine = new SIAE_UTIL_TaxEngine();

        Test.startTest();
        SIAE_UTIL_TaxEngine.QuoteHeader header = engine.resolveQuoteHeader(quote.Id);

        Boolean blankThrown = false;
        try { engine.resolveQuoteHeader(''); } catch (Exception e) { blankThrown = true; }

        Boolean notFoundThrown = false;
        try { engine.resolveQuoteHeader('0Q0000000000000AAA'); } catch (Exception e) { notFoundThrown = true; }
        Test.stopTest();

        System.assertEquals('9027071900', header.idSap, 'idSap risolto.');
        System.assertEquals('0906806', header.seprag, 'seprag risolto.');
        System.assert(blankThrown, 'Quote id blank deve lanciare.');
        System.assert(notFoundThrown, 'Quote inesistente deve lanciare.');
    }

    @IsTest
    static void shouldDetectContexts_AndThrowOnInvalid() {
        Quote quote = [SELECT Id FROM Quote LIMIT 1];
        Order ord = [SELECT Id FROM Order LIMIT 1];
        Account acc = [SELECT Id FROM Account LIMIT 1];
        SIAE_UTIL_TaxEngine engine = new SIAE_UTIL_TaxEngine();

        Test.startTest();
        System.assertEquals('QUOTE', String.valueOf(engine.detectContext(quote.Id)));
        System.assertEquals('ORDER', String.valueOf(engine.detectContext(ord.Id)));

        Boolean blank = false, unsupported = false, invalid = false;
        try { engine.detectContext(''); } catch (Exception e) { blank = e.getMessage().contains('blank'); }
        try { engine.detectContext(acc.Id); } catch (Exception e) { unsupported = e.getMessage().contains('Unsupported'); }
        try { engine.detectContext('INVALID_ID'); } catch (Exception e) { invalid = true; }
        Test.stopTest();

        System.assert(blank, 'Blank deve lanciare.');
        System.assert(unsupported, 'Tipo non supportato deve lanciare.');
        System.assert(invalid, 'Id non valido deve lanciare.');
    }

    @IsTest
    static void shouldParsePaymentItems() {
        SIAE_UTIL_TaxEngine engine = new SIAE_UTIL_TaxEngine();
        String validJson = '{"paymentItems": [' +
            '{"itemCode": "A", "amount": "100.50", "type": "DDA"},' +
            '{"itemCode": "B", "amount": "200,75", "type": "DC"},' +
            '{"itemCode": "", "amount": "1.00", "type": "DDA"},' +
            '{"itemCode": "C", "amount": "", "type": "DC"}' +
            ']}';

        Test.startTest();
        List<SIAE_UTIL_TaxEngine.PaymentItemWrapper> items = engine.parsePaymentItems(validJson);
        System.assert(engine.parsePaymentItems(null).isEmpty(), 'Null → vuoto.');
        System.assert(engine.parsePaymentItems('').isEmpty(), 'Blank → vuoto.');
        System.assert(engine.parsePaymentItems('{"x":[]}').isEmpty(), 'Nodo mancante → vuoto.');
        System.assert(engine.parsePaymentItems('{invalid}').isEmpty(), 'JSON invalido → vuoto.');
        Test.stopTest();

        System.assertEquals(2, items.size(), 'Solo voci valide.');
        System.assertEquals(100.50, items[0].amount);
        System.assertEquals(200.75, items[1].amount, 'Virgola italiana convertita.');
    }

    @IsTest
    static void shouldBuildResponses() {
        SIAE_UTIL_TaxEngine engine = new SIAE_UTIL_TaxEngine();

        SIAE_UTIL_TaxEngine.TaxLineResponseInput line =
            new SIAE_UTIL_TaxEngine.TaxLineResponseInput();
        line.lineNumber = '0QL000000000001AAA';
        line.taxCode = 'SIAE';
        line.productCode = 'PROD';
        line.quantity = 1;
        line.amount = 100;

        SIAE_UTIL_TaxEngine.TaxCalcResult calc = new SIAE_UTIL_TaxEngine.TaxCalcResult();
        calc.totalTaxDA = 10; calc.totalTaxDC = 2;
        calc.totalTaxBolloDDA = 2; calc.totalTaxBolloDC = 1; calc.totalTax = 15;

        Map<String, SIAE_UTIL_TaxEngine.TaxCalcResult> byLine =
            new Map<String, SIAE_UTIL_TaxEngine.TaxCalcResult>{ line.lineNumber.left(15) => calc };

        Test.startTest();
        commercetax.LineItemResponse single = engine.buildLineItemResponseFromInput(line, calc);
        commercetax.LineItemResponse nullCalc = engine.buildLineItemResponseFromInput(line, null);
        commercetax.LineItemResponse nullLine = engine.buildLineItemResponseFromInput(null, calc);
        SIAE_UTIL_TaxEngine.TaxResponseBuildResult buildResult =
            engine.buildLineItemResponsesFromInput(
                new List<SIAE_UTIL_TaxEngine.TaxLineResponseInput>{ line }, byLine);
        SIAE_UTIL_TaxEngine.TaxResponseBuildResult nullResult =
            engine.buildLineItemResponsesFromInput(null, null);

        commercetax.AmountDetailsResponse amt = engine.buildAmountDetails(100, 15);
        commercetax.AddressesResponse addr = engine.buildDefaultAddresses();
        commercetax.TaxDetailsResponse agg = engine.buildAggregateTaxDetailsResponse('DA', 10);
        commercetax.ErrorResponse err = engine.buildError('400', 'msg');
        commercetax.CalculateTaxResponse calcNull = engine.buildCalculateTaxResponse(null, null);
        Test.stopTest();

        System.assertNotEquals(null, single);
        System.assertNotEquals(null, nullCalc);
        System.assertNotEquals(null, nullLine);
        System.assertEquals(1, buildResult.lineResponses.size());
        System.assertEquals(15, buildResult.grandTotalTax, 'Totale tasse = TaxCalcResult.');
        System.assertEquals(100, buildResult.grandTotalAmount);
        System.assertEquals(0, nullResult.lineResponses.size());
        System.assertNotEquals(null, amt);
        System.assertNotEquals(null, addr);
        System.assertNotEquals(null, agg);
        System.assertNotEquals(null, err);
        System.assertNotEquals(null, calcNull);
    }

    @IsTest
    static void shouldHandleProcessRequest_WithNullContext() {
        SIAE_UTIL_TaxEngine engine = new SIAE_UTIL_TaxEngine();
        Test.startTest();
        commercetax.TaxEngineResponse response = engine.processRequest(null);
        Test.stopTest();
        System.assertNotEquals(null, response, 'Response non null anche su errore.');
        System.assert(response instanceof commercetax.ErrorResponse, 'Deve essere ErrorResponse.');
    }

    @IsTest
    static void shouldThrowException_WhenSapCalloutFails() {
        Quote quote = [SELECT Id FROM Quote LIMIT 1];
        List<QuoteLineItem> qlis = [SELECT Id FROM QuoteLineItem ORDER BY CreatedDate ASC LIMIT 1];

        commercetax.CalculateTaxRequest request =
            new commercetax.CalculateTaxRequest(commercetax.CalculateTaxType.Actual);
        request.documentCode = 'DOC-SAP-FAIL';
        request.referenceDocumentCode = 'REF-SAP-FAIL';
        request.referenceEntityId = quote.Id;
        request.currencyIsoCode = 'EUR';
        request.transactionDate = System.now();
        request.isCommit = false;
        request.lineItems = new List<commercetax.TaxLineItemRequest>{
            new commercetax.TaxLineItemRequest(
                null, 100, null, 'TEST', 1, String.valueOf(qlis[0].Id), 'SIAE', System.now()
            )
        };

        TaxMock failMock = new TaxMock();
        failMock.statusCode = 500;

        SIAE_UTIL_TaxEngine engine = new SIAE_UTIL_TaxEngine();
        Boolean exceptionThrown = false;

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, failMock);
        try {
            engine.handleCalculateTax(request);
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown,
            'SAP 500 deve lanciare eccezione — non ritornare zero tasse silenzioso.');
    }

    @IsTest
    static void shouldReceiveSapDataAndMarkCached_WhenQuoteContext() {
        Quote quote = [SELECT Id FROM Quote LIMIT 1];
        List<QuoteLineItem> qlis = [SELECT Id FROM QuoteLineItem ORDER BY CreatedDate ASC LIMIT 3];

        List<String> lineIds = new List<String>();
        for (QuoteLineItem qli : qlis) { lineIds.add(String.valueOf(qli.Id)); }

        SIAE_UTIL_TaxEngine engine = new SIAE_UTIL_TaxEngine();
        SIAE_UTIL_TaxEngine.TaxCalculationInput input =
            buildCoreInput(quote.Id, SIAE_UTIL_TaxEngine.ContextType.QUOTE, lineIds);

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new TaxMock());
        SIAE_UTIL_TaxEngine.TaxCalculationOutput output = engine.calculateTaxCore(input);
        Test.stopTest();

        // Verifica che i risultati SAP siano stati ricevuti e inclusi nel calcResultByLineId.
        // RLM persiste il breakdown in QuoteItemTaxItem; ManageTaxes li legge nella stessa transazione.
        for (QuoteLineItem qli : qlis) {
            String lineId15 = String.valueOf(qli.Id).left(15);
            SIAE_UTIL_TaxEngine.TaxCalcResult res = output.calcResultByLineId.get(lineId15);
            System.assertNotEquals(null, res, 'Risultato presente per ogni QLI.');
            System.assertEquals(true,  res.sapDataReceived, 'sapDataReceived=true: SAP ha risposto.');
            System.assertEquals(10.00, res.totalTaxDA,      'DA ricevuto da SAP.');
            System.assertEquals(2.00,  res.totalTaxDC,      'DC ricevuto da SAP.');
            System.assertEquals(2.00,  res.totalTaxBolloDDA,'BolloDA ricevuto da SAP.');
            System.assertEquals(1.00,  res.totalTaxBolloDC, 'BolloDC cached da SAP.');
        }
    }

    @IsTest
    static void shouldHandleCalculateTax_FullFlow_Quote() {
        Quote quote = [SELECT Id FROM Quote LIMIT 1];
        List<QuoteLineItem> qlis = [SELECT Id FROM QuoteLineItem ORDER BY CreatedDate ASC LIMIT 3];

        commercetax.CalculateTaxRequest request =
            new commercetax.CalculateTaxRequest(commercetax.CalculateTaxType.Actual);
        request.documentCode = 'DOC-TEST';
        request.referenceDocumentCode = 'REF-DOC-TEST';
        request.referenceEntityId = quote.Id;
        request.currencyIsoCode = 'EUR';
        request.transactionDate = System.now();
        request.isCommit = false;

        List<commercetax.TaxLineItemRequest> lineItems = new List<commercetax.TaxLineItemRequest>();
        for (QuoteLineItem qli : qlis) {
            lineItems.add(new commercetax.TaxLineItemRequest(
                null, 100, null, 'TEST', 1, String.valueOf(qli.Id), 'SIAE', System.now()
            ));
        }
        request.lineItems = lineItems;

        SIAE_UTIL_TaxEngine engine = new SIAE_UTIL_TaxEngine();

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new TaxMock());
        commercetax.TaxEngineResponse response = engine.handleCalculateTax(request);
        Test.stopTest();

        System.assertNotEquals(null, response, 'Response non null.');
        System.assert(response instanceof commercetax.CalculateTaxResponse, 'Deve essere CalculateTaxResponse.');
    }
}