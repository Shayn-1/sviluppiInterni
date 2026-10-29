/**
 * @description       : 
 * @author            : Domenico Del Prete - domenico.delprete@nttdata.com
 * @group             : NTT Data
 * @last modified on  : 08-07-2026
 * @last modified by  : Domenico Del Prete - domenico.delprete@nttdata.com
**/
@IsTest
private class SIAE_REST_SalvaScheda_T {

    private static final String REF_ID = 'REF-SALVA-SCHEDA-TEST-001';
    private static List<MockResponseSpec> mockResponses = new List<MockResponseSpec>();
    private static Integer mockIndex = 0;

    @TestSetup
    static void setupData() {
        Account acc = new Account(Name = 'Test Account Salva Scheda');
        putIfCreateable(acc, 'SIAE_IDCRM__c', '123456');
        insert acc;

        Id standardPricebookId = Test.getStandardPricebookId();

        Product2 automezzi = new Product2(
            Name = 'Test Automezzi',
            ProductCode = 'SIAE-PROD-AUTOMEZZI',
            IsActive = true
        );
        putIfCreateable(automezzi, 'SIAE_IdTableDDA__c', 'DDA-AUT');
        putIfCreateable(automezzi, 'SIAE_IdTableDDAFlat__c', 'DDAF-AUT');
        putIfCreateable(automezzi, 'SIAE_IdTableDC__c', 'DC-AUT');
        putIfCreateable(automezzi, 'SIAE_IdTableDCFlat__c', 'DCF-AUT');
        insert automezzi;

        Product2 lavoro = new Product2(
            Name = 'Test Ambienti di lavoro',
            ProductCode = 'SIAE-PROD-LAVORO',
            IsActive = true
        );
        putIfCreateable(lavoro, 'SIAE_IdTableDDA__c', 'DDA-LAV');
        putIfCreateable(lavoro, 'SIAE_IdTableDDAFlat__c', 'DDAF-LAV;DDAFV-LAV');
        putIfCreateable(lavoro, 'SIAE_IdTableDC__c', 'DC-LAV');
        putIfCreateable(lavoro, 'SIAE_IdTableDCFlat__c', 'DCF-LAV;DCFV-LAV');
        insert lavoro;

        PricebookEntry pbeAutomezzi = new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = automezzi.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert pbeAutomezzi;

        PricebookEntry pbeLavoro = new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = lavoro.Id,
            UnitPrice = 50,
            IsActive = true
        );
        insert pbeLavoro;

        Order ord = new Order(
            AccountId = acc.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = standardPricebookId
        );
        putIfCreateable(ord, 'SIAE_IncludeDC__c', false);
        putIfCreateable(ord, 'SIAE_ReferenceId__c', REF_ID);
        insert ord;

        insert new List<OrderItem>{
            buildOrderItem(ord.Id, pbeAutomezzi.Id, 100, 'SIAE-PROD-AUTOMEZZI'),
            buildOrderItem(ord.Id, pbeLavoro.Id, 50, 'SIAE-PROD-LAVORO')
        };
    }

    @IsTest
    static void build_from_orderitem_with_injected_attributes() {
        OrderItem automezzi = getOrderItemByProductCode('SIAE-PROD-AUTOMEZZI');
        OrderItem lavoro = getOrderItemByProductCode('SIAE-PROD-LAVORO');

        injectAutomezziAttributes(automezzi.Id);
        injectLavoroAttributes(lavoro.Id);

        Test.startTest();
        try {
            SIAE_REST_SalvaScheda.buildRequestFromOrderItem(automezzi.Id);
        } catch (Exception ex) {
        }
        try {
            SIAE_REST_SalvaScheda.buildRequestFromOrderItem(lavoro.Id);
        } catch (Exception ex) {
        }
        Test.stopTest();
    }

    @IsTest
    static void build_from_order_with_injected_attributes() {
        Order ord = [SELECT Id FROM Order LIMIT 1];
        for (OrderItem oi : [SELECT Id, PricebookEntry.Product2.ProductCode FROM OrderItem WHERE OrderId = :ord.Id]) {
            if (oi.PricebookEntry.Product2.ProductCode == 'SIAE-PROD-AUTOMEZZI') {
                injectAutomezziAttributes(oi.Id);
            } else {
                injectLavoroAttributes(oi.Id);
            }
        }

        Test.startTest();
        try {
            SIAE_REST_SalvaScheda.buildRequestsFromOrder(ord.Id);
        } catch (Exception ex) {
        }
        try {
            SIAE_REST_SalvaScheda.buildRequestsFromOrder(ord.Id);
        } catch (Exception ex) {
        }
        Test.stopTest();
    }

    @IsTest
    static void post_direct_success_and_error_responses() {
        mockResponses = new List<MockResponseSpec>{
            new MockResponseSpec(200, 'OK', '{"idCarrello":"801TEST","idRiferimento":"REF","idSchedaDda":100000518313,"idSchedaDc":100000518314}'),
            new MockResponseSpec(201, 'Created', '{"idCarrello":"801TEST","idRiferimento":"REF","idSchedaDda":"100000518315","idSchedaDc":"100000518316"}'),
            new MockResponseSpec(204, 'No Content', ''),
            new MockResponseSpec(200, 'OK', 'not json'),
            new MockResponseSpec(400, 'Bad Request', '{"code":"KO","message":"Errore test"}'),
            new MockResponseSpec(500, 'Server Error', 'errore plain text')
        };
        mockIndex = 0;
        Test.setMock(HttpCalloutMock.class, new QueueMock());

        Test.startTest();
        for (Integer i = 0; i < 6; i++) {
            try {
                SIAE_REST_SalvaScheda.postSalvaScheda(buildMinimalRequest(), buildHeaders());
            } catch (Exception ex) {
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void post_from_orderitem_and_order_paths() {
        Order ord = [SELECT Id FROM Order LIMIT 1];
        OrderItem automezzi = getOrderItemByProductCode('SIAE-PROD-AUTOMEZZI');
        OrderItem lavoro = getOrderItemByProductCode('SIAE-PROD-LAVORO');

        injectAutomezziAttributes(automezzi.Id);
        injectLavoroAttributes(lavoro.Id);

        mockResponses = new List<MockResponseSpec>{
            new MockResponseSpec(200, 'OK', '{"idCarrello":"801TEST","idRiferimento":"REF","idSchedaDda":100000518313,"idSchedaDc":100000518314}'),
            new MockResponseSpec(200, 'OK', '{"idCarrello":"801TEST","idRiferimento":"REF","idSchedaDda":100000518315,"idSchedaDc":100000518316}'),
            new MockResponseSpec(200, 'OK', '{"idCarrello":"801TEST","idRiferimento":"REF","idSchedaDda":100000518317,"idSchedaDc":100000518318}')
        };
        mockIndex = 0;
        Test.setMock(HttpCalloutMock.class, new QueueMock());

        Test.startTest();
        try {
            SIAE_REST_SalvaScheda.postSalvaSchedaFromOrderItem(automezzi.Id, buildHeaders());
        } catch (Exception ex) {
        }
        try {
            SIAE_REST_SalvaScheda.postSalvaSchedeFromOrder(ord.Id, buildHeaders());
        } catch (Exception ex) {
        }
        Test.stopTest();
    }

    @IsTest
    static void validation_and_incomplete_paths() {
        Test.startTest();
        try {
            SIAE_REST_SalvaScheda.buildRequestFromOrderItem(null);
        } catch (Exception ex) {
        }
        try {
            SIAE_REST_SalvaScheda.buildRequestsFromOrder(null);
        } catch (Exception ex) {
        }
        try {
            SIAE_REST_SalvaScheda.postSalvaScheda(null, buildHeaders());
        } catch (Exception ex) {
        }
        try {
            SIAE_REST_SalvaScheda.postSalvaScheda(new SIAE_REST_SalvaScheda.SalvaSchedaRequest(), buildHeaders());
        } catch (Exception ex) {
        }
        try {
            SIAE_REST_SalvaScheda.postSalvaScheda(buildMinimalRequest(), null);
        } catch (Exception ex) {
        }
        try {
            SIAE_REST_SalvaScheda.postSalvaScheda(buildMinimalRequest(), new SIAE_REST_SalvaScheda.SalvaSchedaHeaders());
        } catch (Exception ex) {
        }
        try {
            SIAE_REST_SalvaScheda.postSalvaSchedaFromOrderItem(getOrderItemByProductCode('SIAE-PROD-AUTOMEZZI').Id, buildHeaders());
        } catch (Exception ex) {
        }
        Test.stopTest();
    }

    @IsTest
    static void malformed_payment_items_paths() {
        OrderItem automezzi = getOrderItemByProductCode('SIAE-PROD-AUTOMEZZI');
        OrderItem lavoro = getOrderItemByProductCode('SIAE-PROD-LAVORO');
    
        OrderItem automezziUpdate = new OrderItem(Id = automezzi.Id);
        putIfUpdateable(automezziUpdate, 'SIAE_PaymentItems__c', '{malformed');
    
        OrderItem lavoroUpdate = new OrderItem(Id = lavoro.Id);
        putIfUpdateable(lavoroUpdate, 'SIAE_PaymentItems__c', '{"paymentItems":[]}');
    
        update new List<OrderItem>{ automezziUpdate, lavoroUpdate };
    
        injectAutomezziAttributes(automezzi.Id);
        injectLavoroAttributes(lavoro.Id);
    
        Test.startTest();
        try {
            SIAE_REST_SalvaScheda.buildRequestFromOrderItem(automezzi.Id);
        } catch (Exception ex) {
        }
        try {
            SIAE_REST_SalvaScheda.buildRequestFromOrderItem(lavoro.Id);
        } catch (Exception ex) {
        }
        Test.stopTest();
    }

    @IsTest
    static void idtabella_resolution_non_flat() {
        OrderItem lavoro = getOrderItemByProductCode('SIAE-PROD-LAVORO');
        injectLavoroAttributes(lavoro.Id);

        Test.startTest();
        SIAE_REST_SalvaScheda.SalvaSchedaBuildResult buildResult =
            SIAE_REST_SalvaScheda.buildRequestFromOrderItem(lavoro.Id);
        Test.stopTest();

        System.assertEquals(
            'DDA-LAV',
            buildResult.request.tariffa.idTabella,
            'tariffa.idTabella top-level deve usare il campo DDA non flat.'
        );

        SIAE_REST_SalvaScheda.CostiStrumento costo7b =
            getCostiStrumentoById(buildResult.request.tariffa.costiStrumenti, '7B');
        System.assertNotEquals(null, costo7b, 'Atteso elemento costiStrumenti[] per instrumentId 7B.');
        System.assertNotEquals(null, costo7b.costiDda, 'Atteso costiDda valorizzato per instrumentId 7B.');
        System.assertNotEquals(null, costo7b.costiDc, 'Atteso costiDc valorizzato per instrumentId 7B nello stesso oggetto di costiDda.');
        System.assertEquals(
            'DDA-LAV',
            costo7b.costiDda.idTabella,
            'costiDda.idTabella deve usare il campo DDA non flat.'
        );
        System.assertEquals(
            'DC-LAV',
            costo7b.costiDc.idTabella,
            'costiDc.idTabella deve usare il campo DC non flat.'
        );
    }

    @IsTest
    static void idtabella_resolution_flat() {
        OrderItem lavoro = getOrderItemByProductCode('SIAE-PROD-LAVORO');

        OrderItem lavoroUpdate = new OrderItem(Id = lavoro.Id);
        putIfUpdateable(lavoroUpdate, 'SIAE_TypeOfFlatRate__c', 'FLAT_AUDIO');
        update lavoroUpdate;

        injectLavoroAttributes(lavoro.Id);

        Test.startTest();
        SIAE_REST_SalvaScheda.SalvaSchedaBuildResult buildResult =
            SIAE_REST_SalvaScheda.buildRequestFromOrderItem(lavoro.Id);
        Test.stopTest();

        System.assertEquals(
            'DDAF-LAV',
            buildResult.request.tariffa.idTabella,
            'tariffa.idTabella top-level deve usare il campo DDA flat.'
        );

        SIAE_REST_SalvaScheda.CostiStrumento costoDda =
            getCostiStrumentoByIdAndType(buildResult.request.tariffa.costiStrumenti, '7B', true);
        SIAE_REST_SalvaScheda.CostiStrumento costoDc =
            getCostiStrumentoByIdAndType(buildResult.request.tariffa.costiStrumenti, '7B', false);
        System.assertNotEquals(null, costoDda, 'Atteso elemento costiStrumenti[] DDA per instrumentId 7B.');
        System.assertNotEquals(null, costoDc, 'Atteso elemento costiStrumenti[] DC per instrumentId 7B.');
        System.assertEquals(
            'DDAF-LAV',
            costoDda.costiDda.idTabella,
            'costiDda.idTabella deve usare il campo DDA flat.'
        );
        System.assertEquals(
            'DCF-LAV',
            costoDc.costiDc.idTabella,
            'costiDc.idTabella deve usare il campo DC flat.'
        );
    }

    @IsTest
    static void idtabella_resolution_flat_audio_video() {
        OrderItem lavoro = getOrderItemByProductCode('SIAE-PROD-LAVORO');

        OrderItem lavoroUpdate = new OrderItem(Id = lavoro.Id);
        putIfUpdateable(lavoroUpdate, 'SIAE_TypeOfFlatRate__c', 'FLAT_AUDIO_VIDEO');
        update lavoroUpdate;

        injectLavoroAttributes(lavoro.Id);

        Test.startTest();
        SIAE_REST_SalvaScheda.SalvaSchedaBuildResult buildResult =
            SIAE_REST_SalvaScheda.buildRequestFromOrderItem(lavoro.Id);
        Test.stopTest();

        System.assertEquals(
            'DDAFV-LAV',
            buildResult.request.tariffa.idTabella,
            'tariffa.idTabella top-level deve usare il 2o valore (audio+video) del campo DDA flat.'
        );

        SIAE_REST_SalvaScheda.CostiStrumento costoDda =
            getCostiStrumentoByIdAndType(buildResult.request.tariffa.costiStrumenti, '7B', true);
        SIAE_REST_SalvaScheda.CostiStrumento costoDc =
            getCostiStrumentoByIdAndType(buildResult.request.tariffa.costiStrumenti, '7B', false);
        System.assertNotEquals(null, costoDda, 'Atteso elemento costiStrumenti[] DDA per instrumentId 7B.');
        System.assertNotEquals(null, costoDc, 'Atteso elemento costiStrumenti[] DC per instrumentId 7B.');
        System.assertEquals(
            'DDAFV-LAV',
            costoDda.costiDda.idTabella,
            'costiDda.idTabella deve usare il 2o valore (audio+video) del campo DDA flat.'
        );
        System.assertEquals(
            'DCFV-LAV',
            costoDc.costiDc.idTabella,
            'costiDc.idTabella deve usare il 2o valore (audio+video) del campo DC flat.'
        );
    }

    @IsTest
    static void costiStrumenti_splits_dda_and_dc_sharing_same_instrumentId() {
        OrderItem lavoro = getOrderItemByProductCode('SIAE-PROD-LAVORO');

        OrderItem lavoroUpdate = new OrderItem(Id = lavoro.Id);
        putIfUpdateable(lavoroUpdate, 'SIAE_PaymentItems__c', buildSharedInstrumentPaymentItemsJson());
        update lavoroUpdate;

        SIAE_REST_SalvaScheda.setTestOrderItemAttributeValues(lavoro.Id, new Map<String, String>{
            'SIAE-ATTR-TV-UND40-CAM' => '20',
            'SIAE-ATTR-TV-OVR40' => '1'
        });

        Test.startTest();
        SIAE_REST_SalvaScheda.SalvaSchedaBuildResult buildResult =
            SIAE_REST_SalvaScheda.buildRequestFromOrderItem(lavoro.Id);
        Test.stopTest();

        List<SIAE_REST_SalvaScheda.CostiStrumento> costiStrumento5 = new List<SIAE_REST_SalvaScheda.CostiStrumento>();
        for (SIAE_REST_SalvaScheda.CostiStrumento costo : buildResult.request.tariffa.costiStrumenti) {
            if (costo != null && '5'.equals(costo.idStrumento)) { costiStrumento5.add(costo); }
        }

        /*
         * SIAE-ATTR-TV-UND40-CAM e SIAE-ATTR-TV-OVR40 generano due occorrenze
         * distinte di idStrumento 5 in scheda.strumenti[]. I PaymentItem del
         * fixture di questo test non hanno attributeCode (sono JSON costruito
         * a mano, non passano da SIAE_UTIL_VoceIncassoEngine.toPaymentItem),
         * quindi il match per attributo non puo' scattare e si ricade sul
         * fallback, che pero' NON e' la stessa regola per DDA e per DC FLAT:
         * - AC/LC (DDA, non FLAT) vengono assegnati per idStrumento
         *   all'ULTIMA occorrenza di scheda.strumenti[] con quello stesso
         *   idStrumento;
         * - il FLAT (0780, revenueItemType FLAT) segue invece la regola "di
         *   scheda": l'importo reale va alla PRIMA occorrenza di
         *   scheda.strumenti[] in assoluto.
         * Con solo due occorrenze totali (entrambe idStrumento 5), le due
         * regole selezionano quindi elementi DIVERSI: un elemento ha il DDA
         * reale e il DC placeholder a 0, l'altro il DC reale e il DDA
         * placeholder a 0. costiDda e costiDc restano comunque sempre uniti
         * nello stesso oggetto (mai null), come atteso da SPORT.
         */
        System.assertEquals(
            2,
            costiStrumento5.size(),
            'idStrumento 5 ha due occorrenze in scheda.strumenti[] (TV-UND40-CAM e TV-OVR40): un elemento costiStrumenti[] per ciascuna, con costiDda e costiDc sempre uniti nello stesso oggetto.'
        );

        SIAE_REST_SalvaScheda.CostiStrumento ddaRealCosto = null;
        SIAE_REST_SalvaScheda.CostiStrumento dcRealCosto = null;

        for (SIAE_REST_SalvaScheda.CostiStrumento costo : costiStrumento5) {
            System.assertNotEquals(null, costo.costiDda, 'Atteso costiDda sempre valorizzato per ogni occorrenza di idStrumento 5.');
            System.assertNotEquals(null, costo.costiDc, 'Atteso costiDc sempre valorizzato per ogni occorrenza di idStrumento 5.');

            for (SIAE_REST_SalvaScheda.VoceCosto voce : costo.costiDda.vociCosto) {
                if (voce.importo > 0) { ddaRealCosto = costo; }
            }
            for (SIAE_REST_SalvaScheda.VoceCosto voce : costo.costiDc.vociCosto) {
                if (voce.importo > 0) { dcRealCosto = costo; }
            }
        }

        System.assertNotEquals(null, ddaRealCosto, 'Atteso un elemento con i PaymentItem DDA reali (AC/LC).');
        System.assertNotEquals(null, dcRealCosto, 'Atteso un elemento con il PaymentItem DC FLAT reale.');
        System.assertNotEquals(
            ddaRealCosto,
            dcRealCosto,
            'DDA (ultima occorrenza per idStrumento) e DC FLAT (prima occorrenza di scheda) seguono regole diverse: devono selezionare elementi diversi.'
        );

        System.assertEquals(
            2,
            ddaRealCosto.costiDda.vociCosto.size(),
            'AC e LC condividono lo stesso instrumentId e devono restare uniti nello stesso costiDda.vociCosto[].'
        );
        for (SIAE_REST_SalvaScheda.VoceCosto voce : ddaRealCosto.costiDda.vociCosto) {
            System.assert(voce.importo > 0, 'L\'occorrenza rappresentativa DDA deve avere gli importi reali, non 0.');
        }
        for (SIAE_REST_SalvaScheda.VoceCosto voce : ddaRealCosto.costiDc.vociCosto) {
            System.assertEquals(0, voce.importo, 'L\'occorrenza rappresentativa DDA non e\' la prima in assoluto: il DC FLAT deve essere a 0.');
        }

        System.assertEquals(
            1,
            dcRealCosto.costiDc.vociCosto.size(),
            'Atteso un solo voceCosto FLAT per costiDc sull\'occorrenza rappresentativa DC.'
        );
        System.assertEquals(
            120.01,
            dcRealCosto.costiDc.vociCosto[0].importo,
            'L\'occorrenza rappresentativa DC deve avere l\'importo FLAT reale.'
        );
        System.assertEquals(
            TIPO_PAGAMENTO_FLAT_EXPECTED,
            dcRealCosto.costiDc.tipoPagamento,
            'costiDc con vociCosto di tipo FLAT deve avere tipoPagamento FLAT, non APPARECCHIO.'
        );
        for (SIAE_REST_SalvaScheda.VoceCosto voce : dcRealCosto.costiDda.vociCosto) {
            System.assertEquals(0, voce.importo, 'L\'occorrenza rappresentativa DC non e\' l\'ultima per idStrumento 5: il DDA deve essere a 0.');
        }
    }

    private static final String TIPO_PAGAMENTO_FLAT_EXPECTED = 'FLAT';

    /*
     * UAT Negozi: sotto i 200 mq di area vendita (SIAE-ATTR-QTA) le voci DC
     * calcolate a monte come FLAT devono uscire come tipoPagamento Apparecchio
     * / tipo LC, a parita' di importo. Sopra i 200 mq il comportamento resta
     * quello attuale (FLAT/FLAT).
     */
    @IsTest
    static void costiStrumenti_negozi_sotto_soglia_mq_usa_apparecchio_lc() {
        OrderItem negozi = buildNegoziOrderItemWithDcFlatItems(150);

        Test.startTest();
        SIAE_REST_SalvaScheda.SalvaSchedaBuildResult buildResult =
            SIAE_REST_SalvaScheda.buildRequestFromOrderItem(negozi.Id);
        Test.stopTest();

        SIAE_REST_SalvaScheda.CostiStrumento costo =
            getCostiStrumentoById(buildResult.request.tariffa.costiStrumenti, 'NEG1');
        System.assertNotEquals(null, costo, 'Atteso elemento costiStrumenti[] per instrumentId NEG1.');
        System.assertNotEquals(null, costo.costiDc, 'Atteso costiDc valorizzato per instrumentId NEG1.');

        System.assertEquals(
            'APPARECCHIO',
            costo.costiDc.tipoPagamento,
            'Sotto i 200 mq le voci DC devono uscire come tipoPagamento Apparecchio, non FLAT.'
        );

        System.assertEquals(
            2,
            costo.costiDc.vociCosto.size(),
            'Attese le due vociCosto DC (0787 e 0788), come nel calcolo FLAT esistente.'
        );

        Decimal totale = 0;
        for (SIAE_REST_SalvaScheda.VoceCosto voce : costo.costiDc.vociCosto) {
            System.assertEquals('LC', voce.tipo, 'Sotto i 200 mq il tipo voce DC deve essere LC, non FLAT.');
            totale += voce.importo;
        }
        System.assertEquals(100.00, totale, 'L\'importo complessivo DC non deve cambiare rispetto al calcolo FLAT esistente.');
    }

    @IsTest
    static void costiStrumenti_negozi_sopra_soglia_mq_resta_flat() {
        OrderItem negozi = buildNegoziOrderItemWithDcFlatItems(250);

        Test.startTest();
        SIAE_REST_SalvaScheda.SalvaSchedaBuildResult buildResult =
            SIAE_REST_SalvaScheda.buildRequestFromOrderItem(negozi.Id);
        Test.stopTest();

        SIAE_REST_SalvaScheda.CostiStrumento costo =
            getCostiStrumentoById(buildResult.request.tariffa.costiStrumenti, 'NEG1');
        System.assertNotEquals(null, costo, 'Atteso elemento costiStrumenti[] per instrumentId NEG1.');
        System.assertNotEquals(null, costo.costiDc, 'Atteso costiDc valorizzato per instrumentId NEG1.');

        System.assertEquals(
            TIPO_PAGAMENTO_FLAT_EXPECTED,
            costo.costiDc.tipoPagamento,
            'Sopra i 200 mq il comportamento DC deve restare FLAT, come oggi.'
        );

        Decimal totale = 0;
        for (SIAE_REST_SalvaScheda.VoceCosto voce : costo.costiDc.vociCosto) {
            System.assertEquals(TIPO_PAGAMENTO_FLAT_EXPECTED, voce.tipo, 'Sopra i 200 mq il tipo voce DC deve restare FLAT.');
            totale += voce.importo;
        }
        System.assertEquals(100.00, totale, 'L\'importo complessivo DC non deve cambiare.');
    }

    private static OrderItem buildNegoziOrderItemWithDcFlatItems(Decimal mqAreeVendita) {
        Order ord = [SELECT Id FROM Order LIMIT 1];
        Id standardPricebookId = Test.getStandardPricebookId();

        Product2 negozi = new Product2(
            Name = 'Test Negozi',
            ProductCode = 'SIAE-PROD-NEGOZI',
            IsActive = true
        );
        insert negozi;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = negozi.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert pbe;

        OrderItem oi = new OrderItem(
            OrderId = ord.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 100,
            ServiceDate = Date.today(),
            EndDate = Date.today().addYears(1).addDays(-1)
        );
        putIfCreateable(oi, 'SIAE_TypeOfCoverage__c', 'Annuale');
        putIfCreateable(oi, 'SIAE_TotalDA__c', 100);
        putIfCreateable(oi, 'SIAE_DirittiConnessi__c', 100);
        putIfCreateable(oi, 'SIAE_TotalCommercialAgreement__c', 0);
        putIfCreateable(oi, 'SIAE_DDADiscountPercent__c', 0);
        putIfCreateable(oi, 'SIAE_DCDiscountPercent__c', 0);
        putIfCreateable(oi, 'SIAE_SpaceId__c', '987654');
        putIfCreateable(oi, 'SIAE_GenereName__c', 'Negozio');
        putIfCreateable(oi, 'SIAE_PaymentItems__c', buildNegoziPaymentItemsJson());
        insert oi;

        SIAE_REST_SalvaScheda.setTestOrderItemAttributeValues(oi.Id, new Map<String, String>{
            'SIAE-ATTR-QTA' => String.valueOf(mqAreeVendita)
        });

        return oi;
    }

    private static String buildNegoziPaymentItemsJson() {
        return JSON.serialize(new Map<String, Object>{
            'paymentItems' => new List<Object>{
                new Map<String, Object>{
                    'itemCode' => '2216',
                    'amount' => '169.60',
                    'type' => 'DDA',
                    'revenueItemType' => 'LC',
                    'materialTaxClassification' => 'E',
                    'instrumentId' => 'NEG1'
                },
                new Map<String, Object>{
                    'itemCode' => '0787',
                    'amount' => '60.00',
                    'type' => 'DC',
                    'revenueItemType' => 'FLAT',
                    'materialTaxClassification' => 'E',
                    'instrumentId' => 'NEG1'
                },
                new Map<String, Object>{
                    'itemCode' => '0788',
                    'amount' => '40.00',
                    'type' => 'DC',
                    'revenueItemType' => 'FLAT',
                    'materialTaxClassification' => 'E',
                    'instrumentId' => 'NEG1'
                }
            }
        });
    }

    private static String buildSharedInstrumentPaymentItemsJson() {
        return JSON.serialize(new Map<String, Object>{
            'paymentItems' => new List<Object>{
                new Map<String, Object>{
                    'itemCode' => '2215',
                    'amount' => '844.19',
                    'type' => 'DDA',
                    'revenueItemType' => 'AC',
                    'materialTaxClassification' => 'E',
                    'instrumentId' => '5'
                },
                new Map<String, Object>{
                    'itemCode' => '2216',
                    'amount' => '945.50',
                    'type' => 'DDA',
                    'revenueItemType' => 'LC',
                    'materialTaxClassification' => 'E',
                    'instrumentId' => '5'
                },
                new Map<String, Object>{
                    'itemCode' => '0780',
                    'amount' => '120.01',
                    'type' => 'DC',
                    'revenueItemType' => 'FLAT',
                    'materialTaxClassification' => 'E',
                    'instrumentId' => '5'
                }
            }
        });
    }

    private static SIAE_REST_SalvaScheda.CostiStrumento getCostiStrumentoById(
        List<SIAE_REST_SalvaScheda.CostiStrumento> costiStrumenti,
        String idStrumento
    ) {
        if (costiStrumenti == null) { return null; }
        for (SIAE_REST_SalvaScheda.CostiStrumento costo : costiStrumenti) {
            if (costo != null && idStrumento.equals(costo.idStrumento)) { return costo; }
        }
        return null;
    }

    /*
     * Un idStrumento puo' comparire in due elementi costiStrumenti[] distinti
     * (uno solo costiDda, uno solo costiDc): questo helper individua quello
     * giusto in base al tipo di costo richiesto.
     */
    private static SIAE_REST_SalvaScheda.CostiStrumento getCostiStrumentoByIdAndType(
        List<SIAE_REST_SalvaScheda.CostiStrumento> costiStrumenti,
        String idStrumento,
        Boolean isDda
    ) {
        if (costiStrumenti == null) { return null; }
        for (SIAE_REST_SalvaScheda.CostiStrumento costo : costiStrumenti) {
            if (costo == null || !idStrumento.equals(costo.idStrumento)) { continue; }
            if (isDda && costo.costiDda != null) { return costo; }
            if (!isDda && costo.costiDc != null) { return costo; }
        }
        return null;
    }

    private static void injectAutomezziAttributes(Id orderItemId) {
        SIAE_REST_SalvaScheda.setTestOrderItemAttributeValues(orderItemId, new Map<String, String>{
            'SIAE-ATTR-CLASS' => 'Adibito al dettaglio ambulante',
            'SIAE-ATTR-CILINDRATA' => 'fino a 8 mq / fino a 1.500 cc',
            'SIAE-ATTR-AUDIO' => '2',
            'SIAE-ATTR-RADIO' => '1',
            'SIAE-ATTR-TV-UND40' => '3',
            'SIAE-ATTR-VIDEO' => '1',
            'SIAE-ATTR-QTA' => '0'
        });
    }

    private static void injectLavoroAttributes(Id orderItemId) {
        SIAE_REST_SalvaScheda.setTestOrderItemAttributeValues(orderItemId, new Map<String, String>{
            'SIAE-ATTR-COND-SPE' => 'NO',
            'SIAE-ATTR-AUDIO' => '4',
            'SIAE-ATTR-RADIO' => '2',
            'SIAE-ATTR-TV-OVR40' => '1',
            'SIAE-ATTR-VIDEO' => '1',
            'SIAE-ATTR-QTA' => '10'
        });
    }

    private static OrderItem getOrderItemByProductCode(String productCode) {
        return [
            SELECT Id,
                   OrderId,
                   PricebookEntry.Product2.ProductCode
            FROM OrderItem
            WHERE PricebookEntry.Product2.ProductCode = :productCode
            LIMIT 1
        ];
    }

    private static SIAE_REST_SalvaScheda.SalvaSchedaRequest buildMinimalRequest() {
        SIAE_REST_SalvaScheda.SalvaSchedaRequest request = new SIAE_REST_SalvaScheda.SalvaSchedaRequest();
        request.scheda = new SIAE_REST_SalvaScheda.SchedaData();
        request.tariffa = new SIAE_REST_SalvaScheda.TariffaData();
        request.accordo = new SIAE_REST_SalvaScheda.AccordoInfo();

        request.scheda.tipoSottoscrizione = 'NUOVO';
        request.scheda.tipoPeriodo = 'ANNUALE';
        request.scheda.flagMostra = false;
        request.scheda.statoDda = 'P';
        request.scheda.statoDc = 'V';
        request.scheda.idCarrello = '801TEST';
        request.scheda.idRiferimento = REF_ID;
        request.scheda.idCrmSpazio = 987654;
        request.scheda.idCrmOrganizzatore = 123456;
        request.scheda.dataInizio = Date.today();
        request.scheda.dataFine = Date.today().addYears(1).addDays(-1);
        request.scheda.parametri = new List<SIAE_REST_SalvaScheda.Parametro>{
            new SIAE_REST_SalvaScheda.Parametro('tipoAutomezzo', '4: fino a 8mq e fino a 1500 cc')
        };
        request.scheda.strumenti = new List<SIAE_REST_SalvaScheda.Strumento>();

        request.tariffa.idTabella = 'TAB-TEST';
        request.tariffa.dda = 100;
        request.tariffa.dc = 0;
        request.tariffa.quotaAccordo = 0;
        request.tariffa.importoTotale = 100;
        request.tariffa.vociCosto = new List<SIAE_REST_SalvaScheda.VoceCosto>();
        request.tariffa.altriCosti = new List<SIAE_REST_SalvaScheda.VoceCosto>();
        request.tariffa.costiStrumenti = new List<SIAE_REST_SalvaScheda.CostiStrumento>();

        return request;
    }

    private static OrderItem buildOrderItem(
        Id orderId,
        Id pricebookEntryId,
        Decimal amount,
        String productCode
    ) {
        OrderItem oi = new OrderItem(
            OrderId = orderId,
            PricebookEntryId = pricebookEntryId,
            Quantity = 1,
            UnitPrice = amount,
            ServiceDate = Date.today(),
            EndDate = Date.today().addYears(1).addDays(-1)
        );

        putIfCreateable(oi, 'SIAE_TypeOfCoverage__c', 'Annuale');
        putIfCreateable(oi, 'SIAE_TotalDA__c', amount);
        putIfCreateable(oi, 'SIAE_DirittiConnessi__c', 50);
        putIfCreateable(oi, 'SIAE_TotalCommercialAgreement__c', 0);
        putIfCreateable(oi, 'SIAE_DDADiscountPercent__c', 0);
        putIfCreateable(oi, 'SIAE_DCDiscountPercent__c', 0);
        putIfCreateable(oi, 'SIAE_SpaceId__c', '987654');
        putIfCreateable(oi, 'SIAE_GenereName__c', productCode == 'SIAE-PROD-AUTOMEZZI' ? 'Automezzi' : 'Ambienti di lavoro');
        putIfCreateable(oi, 'SIAE_PaymentItems__c', buildPaymentItemsJson(amount));

        return oi;
    }

    private static String buildPaymentItemsJson(Decimal amount) {
        return JSON.serialize(new Map<String, Object>{
            'paymentItems' => new List<Object>{
                new Map<String, Object>{
                    'itemCode' => '2230',
                    'amount' => String.valueOf(amount.setScale(2)),
                    'type' => 'DDA',
                    'revenueItemType' => 'LC',
                    'materialTaxClassification' => 'E',
                    'instrumentId' => '7B'
                },
                new Map<String, Object>{
                    'itemCode' => '0794',
                    'amount' => '12.34',
                    'type' => 'DC',
                    'revenueItemType' => 'AS',
                    'materialTaxClassification' => 'E',
                    'instrumentId' => '7B'
                },
                new Map<String, Object>{
                    'itemCode' => 'QA001',
                    'amount' => '3.00',
                    'type' => 'QA',
                    'revenueItemType' => 'QA',
                    'materialTaxClassification' => 'E'
                },
                new Map<String, Object>{
                    'itemCode' => '',
                    'amount' => 'ABC',
                    'type' => 'DDA',
                    'revenueItemType' => 'LC',
                    'materialTaxClassification' => 'E'
                },
                new Map<String, Object>{
                    'itemCode' => 'IGNORE',
                    'amount' => '1.00',
                    'type' => 'SI_DDA',
                    'revenueItemType' => 'SI',
                    'materialTaxClassification' => 'E'
                }
            }
        });
    }

    private static SIAE_REST_SalvaScheda.SalvaSchedaHeaders buildHeaders() {
        SIAE_REST_SalvaScheda.SalvaSchedaHeaders headers = new SIAE_REST_SalvaScheda.SalvaSchedaHeaders();
        headers.transactionID = 'TX-TEST';
        headers.sourceSystem = 'SALESFORCE';
        headers.token = 'TOKEN-TEST';
        headers.userId = 'USER-TEST';
        headers.seprag = 'SEPRAG-TEST';
        headers.authorization = 'Bearer test';
        return headers;
    }

    private class MockResponseSpec {
        Integer code;
        String status;
        String body;

        MockResponseSpec(Integer code, String status, String body) {
            this.code = code;
            this.status = status;
            this.body = body;
        }
    } 

    private class QueueMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            Integer currentIndex = mockIndex;
            mockIndex++;

            if (mockResponses == null || mockResponses.isEmpty()) {
                mockResponses = new List<MockResponseSpec>{
                    new MockResponseSpec(200, 'OK', '{"idCarrello":"801TEST","idRiferimento":"REF","idSchedaDda":100000518313,"idSchedaDc":100000518314}')
                };
            }

            if (currentIndex >= mockResponses.size()) {
                currentIndex = mockResponses.size() - 1;
            }

            MockResponseSpec spec = mockResponses[currentIndex];
            HttpResponse response = new HttpResponse();
            response.setStatusCode(spec.code);
            response.setStatus(spec.status);
            response.setHeader('Content-Type', 'application/json');
            response.setBody(spec.body);
            return response;
        }
    }

    private static void putIfCreateable(SObject record, String fieldApiName, Object value) {
        if (record == null || String.isBlank(fieldApiName)) {
            return;
        }

        Map<String, Schema.SObjectField> fields = record.getSObjectType().getDescribe().fields.getMap();
        if (!fields.containsKey(fieldApiName)) {
            return;
        }

        Schema.DescribeFieldResult describe = fields.get(fieldApiName).getDescribe();
        if (!describe.isCreateable()) {
            return;
        }

        record.put(fieldApiName, coerceValue(value, describe.getType()));
    }

    private static void putIfUpdateable(SObject record, String fieldApiName, Object value) {
        if (record == null || String.isBlank(fieldApiName)) {
            return;
        }

        Map<String, Schema.SObjectField> fields = record.getSObjectType().getDescribe().fields.getMap();
        if (!fields.containsKey(fieldApiName)) {
            return;
        }

        Schema.DescribeFieldResult describe = fields.get(fieldApiName).getDescribe();
        if (!describe.isUpdateable()) {
            return;
        }

        record.put(fieldApiName, coerceValue(value, describe.getType()));
    }

    private static Object coerceValue(Object value, Schema.DisplayType fieldType) {
        if (value == null) {
            return null;
        }

        String stringValue = String.valueOf(value);

        if (fieldType == Schema.DisplayType.Boolean) {
            if (value instanceof Boolean) {
                return value;
            }
            return stringValue.equalsIgnoreCase('true');
        }

        if (fieldType == Schema.DisplayType.Integer) {
            return Integer.valueOf(stringValue.replace(',', '.').split('\\.')[0]);
        }

        if (
            fieldType == Schema.DisplayType.Currency ||
            fieldType == Schema.DisplayType.Double ||
            fieldType == Schema.DisplayType.Percent
        ) {
            return Decimal.valueOf(stringValue.replace(',', '.'));
        }

        if (fieldType == Schema.DisplayType.Date) {
            if (value instanceof Date) {
                return value;
            }
            return Date.valueOf(stringValue);
        }

        if (fieldType == Schema.DisplayType.DateTime) {
            if (value instanceof Datetime) {
                return value;
            }
            return Datetime.valueOf(stringValue);
        }

        return stringValue;
    }
    
    @IsTest
    static void fallback_instrument_priority_paths() {
        OrderItem automezzi = getOrderItemByProductCode('SIAE-PROD-AUTOMEZZI');
    
        insertInstrumentPriorityForTest('SIAE-ATTR-RADIO', 1);
        insertRegolaVoceIncassoAttributoForTest('SIAE-ATTR-RADIO', '7B');
    
        OrderItem automezziUpdate = new OrderItem(Id = automezzi.Id);
        putIfUpdateable(
            automezziUpdate,
            'SIAE_PaymentItems__c',
            buildPaymentItemsJsonWithoutInstrument()
        );
        update automezziUpdate;
    
        injectAutomezziAttributes(automezzi.Id);
    
        Test.startTest();
        try {
            SIAE_REST_SalvaScheda.buildRequestFromOrderItem(automezzi.Id);
        } catch (Exception ex) {
        }
        Test.stopTest();
    }
    
    private static String buildPaymentItemsJsonWithoutInstrument() {
        return JSON.serialize(new Map<String, Object>{
            'paymentItems' => new List<Object>{
                new Map<String, Object>{
                    'itemCode' => '2230',
                    'amount' => '100.00',
                    'type' => 'DDA',
                    'revenueItemType' => 'LC',
                    'materialTaxClassification' => 'E'
                },
                new Map<String, Object>{
                    'itemCode' => '0794',
                    'amount' => '12.34',
                    'type' => 'DC',
                    'revenueItemType' => 'AS',
                    'materialTaxClassification' => 'E'
                }
            }
        });
    }
    
    private static void insertInstrumentPriorityForTest(String attributeCode, Decimal priority) {
        SIAE_InstrumentPriority__c row = new SIAE_InstrumentPriority__c(
            Name = 'TEST_PRIORITY_' + attributeCode.replace('-', '_'),
            SIAE_AttributeCode__c = attributeCode,
            SIAE_Priority__c = priority
        );
        insert row;
    }
    
    private static void insertRegolaVoceIncassoAttributoForTest(String attributeCode, String instrumentId) {
        SIAE_RegolaVoceIncassoAttributo__c row = new SIAE_RegolaVoceIncassoAttributo__c(
            Name = 'TEST_RULE_' + attributeCode.replace('-', '_'),
            SIAE_AttributeCode__c = attributeCode,
            SIAE_IdInstrument__c = instrumentId,
            SIAE_Active__c = true
        );
        Database.insert(row, System.AccessLevel.SYSTEM_MODE);
    }

    @IsTest
    static void dro_provider_and_invalid_input_paths() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        try {
            SIAE_REST_SalvaScheda.getProviderAttributes();
        } catch (Exception ex) {
        }
        try {
            SIAE_REST_SalvaScheda.executeCallout('REQ-GUID-NULL', null, null, null, null);
        } catch (Exception ex) {
        }
        try {
            SIAE_REST_SalvaScheda.executeCallout('REQ-GUID-ACC', String.valueOf(acc.Id), null, null, null);
        } catch (Exception ex) {
        }
        try {
            SIAE_REST_SalvaScheda.executeCallout('REQ-GUID-BAD', 'not-an-id', null, null, null);
        } catch (Exception ex) {
        }
        Test.stopTest();
    }

    @IsTest
    static void dro_execute_callout_success_error_and_config_paths() {
        OrderItem automezzi = getOrderItemByProductCode('SIAE-PROD-AUTOMEZZI');
        OrderItem lavoro = getOrderItemByProductCode('SIAE-PROD-LAVORO');

        injectAutomezziAttributes(automezzi.Id);
        injectLavoroAttributes(lavoro.Id);

        mockResponses = new List<MockResponseSpec>{
            new MockResponseSpec(200, 'OK', '{"idCarrello":"801TEST","idRiferimento":"REF","idSchedaDda":100000518401,"idSchedaDc":100000518402}'),
            new MockResponseSpec(400, 'Bad Request', '{"code":"KO_DRO","message":"Errore DRO test"}'),
            new MockResponseSpec(500, 'Server Error', 'errore dro plain text')
        };
        mockIndex = 0;
        Test.setMock(HttpCalloutMock.class, new QueueMock());

        Map<String, Object> attributesWithConfig = new Map<String, Object>{
            'integrationConfigName' => 'SalvaScheda'
        };
        Map<String, Object> attributesBlankConfig = new Map<String, Object>{
            'integrationConfigName' => ''
        };

        Test.startTest();
        try {
            SIAE_REST_SalvaScheda.executeCallout('REQ-GUID-1', String.valueOf(automezzi.Id), '{}', attributesWithConfig, null);
        } catch (Exception ex) {
        }
        try {
            SIAE_REST_SalvaScheda.executeCallout('REQ-GUID-2', String.valueOf(lavoro.Id), '{}', attributesBlankConfig, null);
        } catch (Exception ex) {
        }
        try {
            SIAE_REST_SalvaScheda.executeCallout('REQ-GUID-3', String.valueOf(automezzi.Id), '{}', new Map<String, Object>(), null);
        } catch (Exception ex) {
        }
        Test.stopTest();
    }

    @IsTest
    static void direct_callout_header_and_request_validation_branches() {
        Test.startTest();
        try {
            SIAE_REST_SalvaScheda.postSalvaScheda(buildRequestWithoutScheda(), buildHeaders());
        } catch (Exception ex) {
        }
        try {
            SIAE_REST_SalvaScheda.postSalvaScheda(buildRequestWithoutTariffa(), buildHeaders());
        } catch (Exception ex) {
        }
        try {
            SIAE_REST_SalvaScheda.postSalvaScheda(buildMinimalRequest(), buildHeadersMissing('transactionID'));
        } catch (Exception ex) {
        }
        try {
            SIAE_REST_SalvaScheda.postSalvaScheda(buildMinimalRequest(), buildHeadersMissing('sourceSystem'));
        } catch (Exception ex) {
        }
        try {
            SIAE_REST_SalvaScheda.postSalvaScheda(buildMinimalRequest(), buildHeadersMissing('token'));
        } catch (Exception ex) {
        }
        try {
            SIAE_REST_SalvaScheda.postSalvaScheda(buildMinimalRequest(), buildHeadersMissing('userId'));
        } catch (Exception ex) {
        }
        try {
            SIAE_REST_SalvaScheda.postSalvaScheda(buildMinimalRequest(), buildHeadersMissing('seprag'));
        } catch (Exception ex) {
        }
        Test.stopTest();
    }

    @IsTest
    static void direct_callout_more_response_parsing_paths() {
        mockResponses = new List<MockResponseSpec>{
            new MockResponseSpec(200, 'OK', '{"IDCARRELLO":"801TEST","IDRIFERIMENTO":"REF","IDSCHEDADDA":100000518501.0,"IDSCHEDADC":"100000518502"}'),
            new MockResponseSpec(200, 'OK', '{"idCarrello":"801TEST","idRiferimento":"REF","idSchedaDda":"100000518503.0","idSchedaDc":"VALORE_NON_NUMERICO"}'),
            new MockResponseSpec(202, 'Accepted', '{"idCarrello":"801TEST","idRiferimento":"REF","idSchedaDda":100000518504,"idSchedaDc":100000518505}'),
            new MockResponseSpec(300, 'Multiple Choices', '{"message":"redirect test"}'),
            new MockResponseSpec(418, 'Teapot', '{"message":"solo messaggio"}'),
            new MockResponseSpec(409, 'Conflict', '{"code":"SOLO_CODICE"}')
        };
        mockIndex = 0;
        Test.setMock(HttpCalloutMock.class, new QueueMock());

        SIAE_REST_SalvaScheda.SalvaSchedaHeaders headersNoAuthorization = buildHeaders();
        headersNoAuthorization.authorization = null;

        Test.startTest();
        for (Integer i = 0; i < 6; i++) {
            try {
                SIAE_REST_SalvaScheda.postSalvaScheda(buildMinimalRequest(), headersNoAuthorization);
            } catch (Exception ex) {
            }
        }
        Test.stopTest();
    }

    private static SIAE_REST_SalvaScheda.SalvaSchedaRequest buildRequestWithoutScheda() {
        SIAE_REST_SalvaScheda.SalvaSchedaRequest request = new SIAE_REST_SalvaScheda.SalvaSchedaRequest();
        request.tariffa = new SIAE_REST_SalvaScheda.TariffaData();
        request.accordo = new SIAE_REST_SalvaScheda.AccordoInfo();
        return request;
    }

    private static SIAE_REST_SalvaScheda.SalvaSchedaRequest buildRequestWithoutTariffa() {
        SIAE_REST_SalvaScheda.SalvaSchedaRequest request = new SIAE_REST_SalvaScheda.SalvaSchedaRequest();
        request.scheda = new SIAE_REST_SalvaScheda.SchedaData();
        request.accordo = new SIAE_REST_SalvaScheda.AccordoInfo();
        return request;
    }

    private static SIAE_REST_SalvaScheda.SalvaSchedaHeaders buildHeadersMissing(String fieldName) {
        SIAE_REST_SalvaScheda.SalvaSchedaHeaders headers = buildHeaders();
        if (fieldName == 'transactionID') {
            headers.transactionID = null;
        } else if (fieldName == 'sourceSystem') {
            headers.sourceSystem = null;
        } else if (fieldName == 'token') {
            headers.token = null;
        } else if (fieldName == 'userId') {
            headers.userId = null;
        } else if (fieldName == 'seprag') {
            headers.seprag = null;
        }
        return headers;
    }

    private static OrderItem buildGenericOrderItem(
        Id orderId,
        Id pricebookEntryId,
        Decimal amount,
        String genereName,
        Decimal paymentItemsAmount
    ) {
        OrderItem oi = new OrderItem(
            OrderId = orderId,
            PricebookEntryId = pricebookEntryId,
            Quantity = 1,
            UnitPrice = amount,
            ServiceDate = Date.today(),
            EndDate = Date.today().addYears(1).addDays(-1)
        );

        putIfCreateable(oi, 'SIAE_TypeOfCoverage__c', 'Annuale');
        putIfCreateable(oi, 'SIAE_TotalDA__c', amount);
        putIfCreateable(oi, 'SIAE_DirittiConnessi__c', 0);
        putIfCreateable(oi, 'SIAE_TotalCommercialAgreement__c', 0);
        putIfCreateable(oi, 'SIAE_DDADiscountPercent__c', 0);
        putIfCreateable(oi, 'SIAE_DCDiscountPercent__c', 0);
        putIfCreateable(oi, 'SIAE_SpaceId__c', '987654');
        putIfCreateable(oi, 'SIAE_GenereName__c', genereName);
        putIfCreateable(oi, 'SIAE_PaymentItems__c', buildPaymentItemsJson(paymentItemsAmount));

        return oi;
    }

    @IsTest
    static void genere_locale_and_scheda_parametri_from_real_metadata() {
        Order ord = [SELECT Id FROM Order LIMIT 1];
        Id standardPricebookId = Test.getStandardPricebookId();

        Product2 acconciatori = new Product2(
            Name = 'Test Acconciatori',
            ProductCode = 'SIAE-PROD-ACCONCIATORI',
            IsActive = true
        );
        putIfCreateable(acconciatori, 'SIAE_IdTableDDA__c', 'DDA-CE');
        putIfCreateable(acconciatori, 'SIAE_IdTableDC__c', 'DC-CE');
        insert acconciatori;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = acconciatori.Id,
            UnitPrice = 80,
            IsActive = true
        );
        insert pbe;

        OrderItem acconciatoriItem = buildGenericOrderItem(ord.Id, pbe.Id, 80, 'Centro estetico', 80);
        insert acconciatoriItem;

        SIAE_REST_SalvaScheda.setTestOrderItemAttributeValues(acconciatoriItem.Id, new Map<String, String>{
            'SIAE-ATTR-CLASS' => 'Capelli ed estetica',
            'SIAE-ATTR-QTA' => '35'
        });

        Test.startTest();
        SIAE_REST_SalvaScheda.SalvaSchedaBuildResult buildResult =
            SIAE_REST_SalvaScheda.buildRequestFromOrderItem(acconciatoriItem.Id);
        Test.stopTest();

        System.assertEquals(
            'CE',
            buildResult.resolvedGenereLocaleCode,
            'Genere CE atteso per Centro estetico/SIAE-PROD-ACCONCIATORI risolto da SIAE_GenereLocale__mdt.'
        );

        Map<String, String> paramValueByName = new Map<String, String>();
        for (SIAE_REST_SalvaScheda.Parametro p : buildResult.request.scheda.parametri) {
            paramValueByName.put(p.nome, p.valore);
        }

        System.assertEquals(
            '0',
            paramValueByName.get('Capienza'),
            'Capienza deve usare SIAE_DefaultValue__c quando manca SIAE_AttributeDefinitionCode__c.'
        );
        System.assertEquals(
            '35',
            paramValueByName.get('Numero_Metri_Quadrati'),
            'Numero_Metri_Quadrati deve arrivare dal valore grezzo di SIAE-ATTR-QTA.'
        );
        System.assertEquals(
            'A',
            paramValueByName.get('fasciaAcconciatori'),
            'fasciaAcconciatori deve essere tradotto tramite SIAE_ValueMap__c enumeration.'
        );

        SIAE_REST_SalvaScheda.Parametro emptyParametro = new SIAE_REST_SalvaScheda.Parametro();
        System.assertEquals(null, emptyParametro.nome);

        OrderItem acconciatoriSenzaQta = buildGenericOrderItem(ord.Id, pbe.Id, 80, 'Centro estetico', 80);
        insert acconciatoriSenzaQta;

        SIAE_REST_SalvaScheda.setTestOrderItemAttributeValues(acconciatoriSenzaQta.Id, new Map<String, String>{
            'SIAE-ATTR-CLASS' => 'Capelli ed estetica'
        });

        SIAE_REST_SalvaScheda.SalvaSchedaBuildResult buildResultSenzaQta =
            SIAE_REST_SalvaScheda.buildRequestFromOrderItem(acconciatoriSenzaQta.Id);

        Boolean hasUnresolvedNonRequiredWarning = false;
        for (String warning : buildResultSenzaQta.warnings) {
            if (warning.contains('Numero_Metri_Quadrati') && warning.contains('non trovato o non risolvibile')) { hasUnresolvedNonRequiredWarning = true; }
        }
        System.assert(
            hasUnresolvedNonRequiredWarning,
            'Numero_Metri_Quadrati non risolvibile (SIAE-ATTR-QTA assente, nessun default) deve generare un warning perche il parametro non e required.'
        );
    }

    @IsTest
    static void statoDc_true_when_diritticonnessi_positive_and_includedc_true() {
        Order ord = [SELECT Id FROM Order LIMIT 1];
        Order ordUpdate = new Order(Id = ord.Id);
        putIfUpdateable(ordUpdate, 'SIAE_IncludeDC__c', true);
        update ordUpdate;

        OrderItem automezzi = getOrderItemByProductCode('SIAE-PROD-AUTOMEZZI');
        OrderItem automezziUpdate = new OrderItem(Id = automezzi.Id);
        putIfUpdateable(automezziUpdate, 'SIAE_DirittiConnessi__c', 25);
        update automezziUpdate;

        injectAutomezziAttributes(automezzi.Id);

        Test.startTest();
        SIAE_REST_SalvaScheda.SalvaSchedaBuildResult buildResult =
            SIAE_REST_SalvaScheda.buildRequestFromOrderItem(automezzi.Id);
        Test.stopTest();

        System.assertEquals(
            'P',
            buildResult.request.scheda.statoDc,
            'statoDc deve essere P quando SIAE_DirittiConnessi__c > 0 e Order.SIAE_IncludeDC__c = true.'
        );
    }

    @IsTest
    static void statoDc_false_when_diritticonnessi_positive_and_includedc_false() {
        OrderItem lavoro = getOrderItemByProductCode('SIAE-PROD-LAVORO');
        OrderItem lavoroUpdate = new OrderItem(Id = lavoro.Id);
        putIfUpdateable(lavoroUpdate, 'SIAE_DirittiConnessi__c', 25);
        update lavoroUpdate;

        injectLavoroAttributes(lavoro.Id);

        Test.startTest();
        SIAE_REST_SalvaScheda.SalvaSchedaBuildResult buildResult =
            SIAE_REST_SalvaScheda.buildRequestFromOrderItem(lavoro.Id);
        Test.stopTest();

        System.assertEquals(
            'V',
            buildResult.request.scheda.statoDc,
            'statoDc deve essere V quando SIAE_DirittiConnessi__c > 0 e Order.SIAE_IncludeDC__c = false (default).'
        );
    }

    /*
     * Licenza che non prevede diritti connessi (SIAE_DirittiConnessi__c = 0):
     * scheda.statoDc, tariffa.dc (mai negativo, fisso a 0) e
     * tariffa.costiStrumenti[].costiDc non devono essere veicolati verso SPORT,
     * anche se SIAE_PaymentItems__c contiene ancora un PaymentItem DC (es.
     * residuo di un calcolo a monte che non e' stato ripulito).
     */
    @IsTest
    static void dc_non_veicolato_quando_licenza_senza_diritti_connessi_zero() {
        OrderItem lavoro = getOrderItemByProductCode('SIAE-PROD-LAVORO');
        OrderItem lavoroUpdate = new OrderItem(Id = lavoro.Id);
        putIfUpdateable(lavoroUpdate, 'SIAE_DirittiConnessi__c', 0);
        update lavoroUpdate;

        injectLavoroAttributes(lavoro.Id);

        Test.startTest();
        SIAE_REST_SalvaScheda.SalvaSchedaBuildResult buildResult =
            SIAE_REST_SalvaScheda.buildRequestFromOrderItem(lavoro.Id);
        Test.stopTest();

        System.assertEquals(
            null,
            buildResult.request.scheda.statoDc,
            'scheda.statoDc non deve essere veicolato per una licenza senza diritti connessi (SIAE_DirittiConnessi__c = 0).'
        );
        System.assertEquals(
            0,
            buildResult.request.tariffa.dc,
            'tariffa.dc deve essere fisso a 0, mai negativo, per una licenza senza diritti connessi.'
        );

        SIAE_REST_SalvaScheda.CostiStrumento costo7b =
            getCostiStrumentoById(buildResult.request.tariffa.costiStrumenti, '7B');
        System.assertNotEquals(null, costo7b, 'Atteso comunque elemento costiStrumenti[] per instrumentId 7B (costiDda resta valorizzato).');
        System.assertNotEquals(null, costo7b.costiDda, 'costiDda deve restare valorizzato indipendentemente dai diritti connessi.');
        System.assertEquals(
            null,
            costo7b.costiDc,
            'costiDc non deve essere veicolato quando la licenza non prevede diritti connessi, anche se SIAE_PaymentItems__c contiene un PaymentItem DC.'
        );
    }

    /*
     * Stesso scenario del test precedente ma con SIAE_DirittiConnessi__c non
     * valorizzato (null) invece che 0: deve essere trattato allo stesso modo.
     */
    @IsTest
    static void dc_non_veicolato_quando_licenza_senza_diritti_connessi_null() {
        OrderItem automezzi = getOrderItemByProductCode('SIAE-PROD-AUTOMEZZI');
        OrderItem automezziUpdate = new OrderItem(Id = automezzi.Id);
        putIfUpdateable(automezziUpdate, 'SIAE_DirittiConnessi__c', null);
        update automezziUpdate;

        injectAutomezziAttributes(automezzi.Id);

        Test.startTest();
        SIAE_REST_SalvaScheda.SalvaSchedaBuildResult buildResult =
            SIAE_REST_SalvaScheda.buildRequestFromOrderItem(automezzi.Id);
        Test.stopTest();

        System.assertEquals(
            null,
            buildResult.request.scheda.statoDc,
            'scheda.statoDc non deve essere veicolato quando SIAE_DirittiConnessi__c non e valorizzato.'
        );
        System.assertEquals(
            0,
            buildResult.request.tariffa.dc,
            'tariffa.dc deve essere fisso a 0 quando SIAE_DirittiConnessi__c non e valorizzato.'
        );

        System.assert(
            !buildResult.request.tariffa.costiStrumenti.isEmpty(),
            'tariffa.costiStrumenti[] deve restare valorizzato (con il solo costiDda) anche senza diritti connessi.'
        );
        for (SIAE_REST_SalvaScheda.CostiStrumento costo : buildResult.request.tariffa.costiStrumenti) {
            System.assertEquals(
                null,
                costo.costiDc,
                'costiDc non deve essere veicolato per nessuno strumento quando la licenza non prevede diritti connessi.'
            );
        }
    }

    /*
     * Licenza con diritti connessi in cui solo alcuni strumenti hanno
     * PaymentItem DC (es. DC 0785 solo su instrumentId 5, mentre 11 e 7A
     * hanno solo DDA): per gli strumenti senza PaymentItem DC costiDc non
     * deve essere veicolato, altrimenti la validazione segnala
     * costiDc.vociCosto[] e costiDc.idTabella mancanti.
     */
    @IsTest
    static void costiDc_non_veicolato_per_strumento_senza_payment_item_dc() {
        OrderItem lavoro = getOrderItemByProductCode('SIAE-PROD-LAVORO');
        OrderItem lavoroUpdate = new OrderItem(Id = lavoro.Id);
        putIfUpdateable(lavoroUpdate, 'SIAE_PaymentItems__c', JSON.serialize(new Map<String, Object>{
            'paymentItems' => new List<Object>{
                new Map<String, Object>{
                    'itemCode' => '2230',
                    'amount' => '50.00',
                    'type' => 'DDA',
                    'revenueItemType' => 'LC',
                    'materialTaxClassification' => 'E',
                    'instrumentId' => '7B'
                },
                new Map<String, Object>{
                    'itemCode' => '0794',
                    'amount' => '12.34',
                    'type' => 'DC',
                    'revenueItemType' => 'LC',
                    'materialTaxClassification' => 'E',
                    'instrumentId' => '7B'
                },
                new Map<String, Object>{
                    'itemCode' => '2229',
                    'amount' => '735.50',
                    'type' => 'DDA',
                    'revenueItemType' => 'LC',
                    'materialTaxClassification' => 'E',
                    'instrumentId' => '7A'
                }
            }
        }));
        update lavoroUpdate;

        injectLavoroAttributes(lavoro.Id);

        Test.startTest();
        SIAE_REST_SalvaScheda.SalvaSchedaBuildResult buildResult =
            SIAE_REST_SalvaScheda.buildRequestFromOrderItem(lavoro.Id);
        Test.stopTest();

        SIAE_REST_SalvaScheda.CostiStrumento costo7a =
            getCostiStrumentoById(buildResult.request.tariffa.costiStrumenti, '7A');
        System.assertNotEquals(null, costo7a, 'Atteso elemento costiStrumenti[] per instrumentId 7A.');
        System.assertNotEquals(null, costo7a.costiDda, 'Atteso costiDda valorizzato per instrumentId 7A.');
        System.assertEquals(
            null,
            costo7a.costiDc,
            'costiDc non deve essere veicolato per uno strumento senza PaymentItem DC.'
        );

        SIAE_REST_SalvaScheda.CostiStrumento costo7b =
            getCostiStrumentoById(buildResult.request.tariffa.costiStrumenti, '7B');
        System.assertNotEquals(null, costo7b.costiDc, 'costiDc deve restare valorizzato per lo strumento con PaymentItem DC.');

        for (String missing : buildResult.missingParameters) {
            System.assert(
                !missing.contains('costiStrumenti[].costiDc'),
                'Nessun parametro costiDc deve risultare mancante: ' + missing
            );
        }
    }

    @IsTest
    static void accordo_present_with_and_without_sconto_values() {
        OrderItem lavoro = getOrderItemByProductCode('SIAE-PROD-LAVORO');
        OrderItem lavoroUpdate = new OrderItem(Id = lavoro.Id);
        putIfUpdateable(lavoroUpdate, 'SIAE_CommercialAgreementCode__c', 'ACC-001');
        putIfUpdateable(lavoroUpdate, 'SIAE_DCDiscountPercent__c', 0.10);
        putIfUpdateable(lavoroUpdate, 'SIAE_DDADiscountPercent__c', 0.05);
        update lavoroUpdate;

        injectLavoroAttributes(lavoro.Id);

        Test.startTest();
        SIAE_REST_SalvaScheda.SalvaSchedaBuildResult buildResultWithDiscounts =
            SIAE_REST_SalvaScheda.buildRequestFromOrderItem(lavoro.Id);
        Test.stopTest();

        System.assertNotEquals(
            null,
            buildResultWithDiscounts.request.accordo,
            'accordo non deve essere nullo quando codiceAccordo e valorizzato.'
        );
        System.assertEquals(10, buildResultWithDiscounts.request.accordo.percentualeScontoDc, 'percentualeScontoDc deve essere la frazione 0.10 convertita in percentuale intera 10 per SPORT.');
        System.assertEquals(5, buildResultWithDiscounts.request.accordo.percentualeScontoDda, 'percentualeScontoDda deve essere la frazione 0.05 convertita in percentuale intera 5 per SPORT.');

        OrderItem automezzi = getOrderItemByProductCode('SIAE-PROD-AUTOMEZZI');
        OrderItem automezziUpdate = new OrderItem(Id = automezzi.Id);
        putIfUpdateable(automezziUpdate, 'SIAE_CommercialAgreementCode__c', 'ACC-002');
        putIfUpdateable(automezziUpdate, 'SIAE_DCDiscountPercent__c', null);
        putIfUpdateable(automezziUpdate, 'SIAE_DDADiscountPercent__c', null);
        update automezziUpdate;

        injectAutomezziAttributes(automezzi.Id);

        SIAE_REST_SalvaScheda.SalvaSchedaBuildResult buildResultNullDiscounts =
            SIAE_REST_SalvaScheda.buildRequestFromOrderItem(automezzi.Id);

        System.assertNotEquals(null, buildResultNullDiscounts.request.accordo);
        System.assertEquals(0, buildResultNullDiscounts.request.accordo.percentualeScontoDc);
        System.assertEquals(0, buildResultNullDiscounts.request.accordo.percentualeScontoDda);
    }

    @IsTest
    static void importo_totale_missing_when_all_amount_fields_null() {
        OrderItem automezzi = getOrderItemByProductCode('SIAE-PROD-AUTOMEZZI');
        OrderItem automezziUpdate = new OrderItem(Id = automezzi.Id);
        putIfUpdateable(automezziUpdate, 'SIAE_TotalDA__c', null);
        putIfUpdateable(automezziUpdate, 'SIAE_DirittiConnessi__c', null);
        putIfUpdateable(automezziUpdate, 'SIAE_TotalCommercialAgreement__c', null);
        update automezziUpdate;

        injectAutomezziAttributes(automezzi.Id);

        Test.startTest();
        SIAE_REST_SalvaScheda.SalvaSchedaBuildResult buildResult =
            SIAE_REST_SalvaScheda.buildRequestFromOrderItem(automezzi.Id);
        Test.stopTest();

        Boolean hasImportoTotaleMissing = false;
        for (String missing : buildResult.missingParameters) {
            if (missing.startsWith('tariffa.importoTotale')) { hasImportoTotaleMissing = true; }
        }
        System.assert(
            hasImportoTotaleMissing,
            'tariffa.importoTotale deve risultare tra i missingParameters quando DA, DC e quotaAccordo sono tutti nulli.'
        );
    }

    @IsTest
    static void postSalvaScheda_with_blank_idCarrello_resolves_null_transaction_id() {
        SIAE_REST_SalvaScheda.SalvaSchedaRequest request = buildMinimalRequest();
        request.scheda.idCarrello = null;

        mockResponses = new List<MockResponseSpec>{
            new MockResponseSpec(200, 'OK', '{"idCarrello":"801TEST","idRiferimento":"REF","idSchedaDda":100000518601,"idSchedaDc":100000518602}')
        };
        mockIndex = 0;
        Test.setMock(HttpCalloutMock.class, new QueueMock());

        Test.startTest();
        try {
            SIAE_REST_SalvaScheda.postSalvaScheda(request, buildHeaders());
        } catch (Exception ex) {
        }
        Test.stopTest();
    }

    @IsTest
    static void dro_error_message_variants_and_response_parsing_edge_cases() {
        OrderItem automezzi = getOrderItemByProductCode('SIAE-PROD-AUTOMEZZI');
        injectAutomezziAttributes(automezzi.Id);

        mockResponses = new List<MockResponseSpec>{
            new MockResponseSpec(400, 'Bad Request', '{"message":"solo messaggio"}'),
            new MockResponseSpec(409, 'Conflict', '{"code":"SOLO_CODICE"}'),
            new MockResponseSpec(404, 'Not Found', ''),
            new MockResponseSpec(200, 'OK', '{"idCarrello":"801TEST","idRiferimento":"REF","idSchedaDda":"100000518501.55","idSchedaDc":100000518702}'),
            new MockResponseSpec(200, 'OK', '{"idCarrello":"x","idRiferimento":"y","idSchedaDda":100000518703}')
        };
        mockIndex = 0;
        Test.setMock(HttpCalloutMock.class, new QueueMock());

        Map<String, Object> attributesWithConfig = new Map<String, Object>{ 'integrationConfigName' => 'SalvaScheda' };

        Test.startTest();
        for (Integer i = 0; i < 5; i++) {
            try {
                SIAE_REST_SalvaScheda.executeCallout('REQ-GUID-EDGE-' + i, String.valueOf(automezzi.Id), '{}', attributesWithConfig, null);
            } catch (Exception ex) {
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void real_orderitemattribute_query_path_with_no_rows_found() {
        /*
         * AttributeDefinition non e' inseribile con una insert/Database.insertImmediate
         * standard dentro una classe di test in questa org (blocco di piattaforma:
         * "Argument must be of internal/virtual sObject type"), quindi non e'
         * possibile inserire OrderItemAttribute reali collegati a una nuova
         * AttributeDefinition all'interno di @IsTest. Questo test copre comunque
         * il ramo query reale (bypass @TestVisible non usato) per il caso senza
         * alcun OrderItemAttribute presente sull'OrderItem.
         */
        Order ord = [SELECT Id FROM Order LIMIT 1];
        Id standardPricebookId = Test.getStandardPricebookId();

        Product2 realAttrProduct = new Product2(
            Name = 'Test RealAttr',
            ProductCode = 'SIAE-PROD-REALATTR',
            IsActive = true
        );
        putIfCreateable(realAttrProduct, 'SIAE_IdTableDDA__c', 'DDA-RA');
        putIfCreateable(realAttrProduct, 'SIAE_IdTableDC__c', 'DC-RA');
        insert realAttrProduct;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = realAttrProduct.Id,
            UnitPrice = 60,
            IsActive = true
        );
        insert pbe;

        OrderItem withoutAnyAttribute = buildGenericOrderItem(ord.Id, pbe.Id, 60, null, 60);
        insert withoutAnyAttribute;

        Test.startTest();
        SIAE_REST_SalvaScheda.SalvaSchedaBuildResult buildResultWithoutAttribute =
            SIAE_REST_SalvaScheda.buildRequestFromOrderItem(withoutAnyAttribute.Id);
        Test.stopTest();

        Boolean foundNoAttributeMissingParameter = false;
        for (String missing : buildResultWithoutAttribute.missingParameters) {
            if (missing.contains('nessun OrderItemAttribute trovato')) { foundNoAttributeMissingParameter = true; }
        }
        System.assert(
            foundNoAttributeMissingParameter,
            'Un OrderItem senza alcun OrderItemAttribute reale deve generare il missingParameter scheda.strumenti tramite query reale.'
        );
    }

    @IsTest
    static void missing_idtabella_when_product_tables_blank() {
        Order ord = [SELECT Id FROM Order LIMIT 1];
        Id standardPricebookId = Test.getStandardPricebookId();

        Product2 blankTablesProduct = new Product2(
            Name = 'Test Blank Tables',
            ProductCode = 'SIAE-PROD-BLANKTABLES',
            IsActive = true
        );
        insert blankTablesProduct;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = blankTablesProduct.Id,
            UnitPrice = 50,
            IsActive = true
        );
        insert pbe;

        OrderItem oi = new OrderItem(
            OrderId = ord.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 50,
            ServiceDate = Date.today(),
            EndDate = Date.today().addYears(1).addDays(-1)
        );
        putIfCreateable(oi, 'SIAE_TypeOfCoverage__c', 'Annuale');
        putIfCreateable(oi, 'SIAE_TotalDA__c', 50);
        putIfCreateable(oi, 'SIAE_DirittiConnessi__c', 5);
        putIfCreateable(oi, 'SIAE_TotalCommercialAgreement__c', 0);
        putIfCreateable(oi, 'SIAE_SpaceId__c', '987654');
        putIfCreateable(oi, 'SIAE_GenereName__c', 'Blank Tables Genere');
        putIfCreateable(oi, 'SIAE_PaymentItems__c', JSON.serialize(new Map<String, Object>{
            'paymentItems' => new List<Object>{
                new Map<String, Object>{
                    'itemCode' => '2230',
                    'amount' => '50.00',
                    'type' => 'DDA',
                    'revenueItemType' => 'LC',
                    'materialTaxClassification' => 'E',
                    'instrumentId' => '9Z'
                },
                new Map<String, Object>{
                    'itemCode' => '0794',
                    'amount' => '5.00',
                    'type' => 'DC',
                    'revenueItemType' => 'AS',
                    'materialTaxClassification' => 'E',
                    'instrumentId' => '9Z'
                }
            }
        }));
        insert oi;

        Test.startTest();
        SIAE_REST_SalvaScheda.SalvaSchedaBuildResult buildResult =
            SIAE_REST_SalvaScheda.buildRequestFromOrderItem(oi.Id);
        Test.stopTest();

        Boolean hasMissingDdaIdTabella = false;
        Boolean hasMissingDcIdTabella = false;
        for (String missing : buildResult.missingParameters) {
            if (missing.contains('costiStrumenti[].costiDda.idTabella')) { hasMissingDdaIdTabella = true; }
            if (missing.contains('costiStrumenti[].costiDc.idTabella')) { hasMissingDcIdTabella = true; }
        }
        System.assert(
            hasMissingDdaIdTabella,
            'costiDda.idTabella deve risultare mancante quando Product2.SIAE_IdTableDDA__c non e valorizzato.'
        );
        System.assert(
            hasMissingDcIdTabella,
            'costiDc.idTabella deve risultare mancante quando Product2.SIAE_IdTableDC__c non e valorizzato.'
        );
    }

    @IsTest
    static void fallback_instrument_priority_no_active_rule_warning() {
        OrderItem automezzi = getOrderItemByProductCode('SIAE-PROD-AUTOMEZZI');

        insertInstrumentPriorityForTest('SIAE-ATTR-RADIO', 1);

        OrderItem automezziUpdate = new OrderItem(Id = automezzi.Id);
        putIfUpdateable(automezziUpdate, 'SIAE_PaymentItems__c', buildPaymentItemsJsonWithoutInstrument());
        update automezziUpdate;

        injectAutomezziAttributes(automezzi.Id);

        Test.startTest();
        SIAE_REST_SalvaScheda.SalvaSchedaBuildResult buildResult =
            SIAE_REST_SalvaScheda.buildRequestFromOrderItem(automezzi.Id);
        Test.stopTest();

        Boolean foundNoActiveRuleWarning = false;
        for (String warning : buildResult.warnings) {
            if (warning.contains('non hanno una SIAE_RegolaVoceIncassoAttributo__c attiva')) { foundNoActiveRuleWarning = true; }
        }
        System.assert(
            foundNoActiveRuleWarning,
            'Deve avvisare che gli attributi prioritari non hanno una regola attiva quando SIAE_RegolaVoceIncassoAttributo__c non e configurata.'
        );
    }

    @IsTest
    static void instrument_priority_rows_tie_and_null_priority_sorting() {
        insertInstrumentPriorityForTest('SIAE-ATTR-RADIO', 1);
        insertInstrumentPriorityForTest('SIAE-ATTR-AUDIO', 1);
        insertInstrumentPriorityForTest('SIAE-ATTR-VIDEO', null);
        insertRegolaVoceIncassoAttributoForTest('SIAE-ATTR-RADIO', '7B');

        OrderItem automezzi = getOrderItemByProductCode('SIAE-PROD-AUTOMEZZI');
        OrderItem automezziUpdate = new OrderItem(Id = automezzi.Id);
        putIfUpdateable(automezziUpdate, 'SIAE_PaymentItems__c', buildPaymentItemsJsonWithoutInstrument());
        update automezziUpdate;

        injectAutomezziAttributes(automezzi.Id);

        Test.startTest();
        SIAE_REST_SalvaScheda.SalvaSchedaBuildResult buildResult =
            SIAE_REST_SalvaScheda.buildRequestFromOrderItem(automezzi.Id);
        Test.stopTest();

        Boolean fallbackResolved = false;
        for (String assumption : buildResult.assumptions) {
            if (assumption.contains('fallback instrumentId risolto con attributo prioritario')) { fallbackResolved = true; }
        }
        System.assert(
            fallbackResolved,
            'Il fallback instrumentId deve risolversi correttamente anche con priorita in parita e valori null nel Custom Setting.'
        );
    }

    @IsTest
    static void malformed_payment_items_itemcode_present_amount_invalid() {
        OrderItem lavoro = getOrderItemByProductCode('SIAE-PROD-LAVORO');

        OrderItem lavoroUpdate = new OrderItem(Id = lavoro.Id);
        putIfUpdateable(lavoroUpdate, 'SIAE_PaymentItems__c', JSON.serialize(new Map<String, Object>{
            'paymentItems' => new List<Object>{
                new Map<String, Object>{
                    'itemCode' => 'BADDDA',
                    'amount' => 'NOTANUMBER',
                    'type' => 'DDA',
                    'revenueItemType' => 'LC',
                    'materialTaxClassification' => 'E',
                    'instrumentId' => '7B'
                },
                new Map<String, Object>{
                    'itemCode' => 'BADQA',
                    'amount' => 'NOTANUMBER',
                    'type' => 'QA',
                    'revenueItemType' => 'QA',
                    'materialTaxClassification' => 'E'
                }
            }
        }));
        update lavoroUpdate;

        injectLavoroAttributes(lavoro.Id);

        Test.startTest();
        SIAE_REST_SalvaScheda.SalvaSchedaBuildResult buildResult =
            SIAE_REST_SalvaScheda.buildRequestFromOrderItem(lavoro.Id);
        Test.stopTest();

        /*
         * tariffa.vociCosto[] e' derivato appiattendo tariffa.costiStrumenti[]
         * (non fa piu' un parsing indipendente dei PaymentItem grezzi), quindi
         * il warning sull'amount non numerico di BADDDA viene emesso una sola
         * volta, con prefisso tariffa.costiStrumenti[].
         */
        Boolean hasAltriCostiAmountWarning = false;
        Boolean hasCostiStrumentiAmountWarning = false;
        for (String warning : buildResult.warnings) {
            if (warning.contains('tariffa.altriCosti[]') && warning.contains('BADQA')) { hasAltriCostiAmountWarning = true; }
            if (warning.contains('tariffa.costiStrumenti[]') && warning.contains('BADDDA')) { hasCostiStrumentiAmountWarning = true; }
        }
        System.assert(hasAltriCostiAmountWarning, 'tariffa.altriCosti[] deve segnalare amount non numerico per BADQA.');
        System.assert(hasCostiStrumentiAmountWarning, 'tariffa.costiStrumenti[] deve segnalare amount non numerico per BADDDA.');
    }

    @IsTest
    static void quantity_parametro_decimal_formatting_and_spaceid_non_numeric() {
        OrderItem lavoro = getOrderItemByProductCode('SIAE-PROD-LAVORO');

        OrderItem lavoroUpdate = new OrderItem(Id = lavoro.Id);
        putIfUpdateable(lavoroUpdate, 'SIAE_SpaceId__c', 'ABC');
        update lavoroUpdate;

        SIAE_REST_SalvaScheda.setTestOrderItemAttributeValues(lavoro.Id, new Map<String, String>{
            'SIAE-ATTR-COND-SPE' => 'NO',
            'SIAE-ATTR-AUDIO' => '4',
            'SIAE-ATTR-RADIO' => '2',
            'SIAE-ATTR-TV-OVR40' => '1.5',
            'SIAE-ATTR-VIDEO' => '1',
            'SIAE-ATTR-QTA' => '10'
        });

        Test.startTest();
        SIAE_REST_SalvaScheda.SalvaSchedaBuildResult buildResult =
            SIAE_REST_SalvaScheda.buildRequestFromOrderItem(lavoro.Id);
        Test.stopTest();

        Boolean hasSpaceIdMissing = false;
        for (String missing : buildResult.missingParameters) {
            if (missing.contains('scheda.idCrmSpazio')) { hasSpaceIdMissing = true; }
        }
        System.assert(
            hasSpaceIdMissing,
            'idCrmSpazio deve risultare mancante quando SIAE_SpaceId__c non e numerico.'
        );

        Boolean hasDecimalQuantityParametro = false;
        for (SIAE_REST_SalvaScheda.Strumento strumento : buildResult.request.scheda.strumenti) {
            for (SIAE_REST_SalvaScheda.Parametro parametro : strumento.parametri) {
                if (parametro.valore == '1.5') { hasDecimalQuantityParametro = true; }
            }
        }
        System.assert(
            hasDecimalQuantityParametro,
            'Un valore quantita con parte decimale reale deve mantenere i decimali in formatQuantity.'
        );
    }

    /**
     * Radio in Store: il palinsesto scelto in Store (AttributeDefinition
     * SIAE-ATTR-PALINSESTO, valore picklist es. "BD") deve arrivare a SPORT come
     * parametro strumento "raggruppamento" sullo stesso idStrumento RS, senza
     * duplicare lo strumento.
     */
    @IsTest
    static void strumento_raggruppamento_da_palinsesto_stringa() {
        OrderItem lavoro = getOrderItemByProductCode('SIAE-PROD-LAVORO');

        SIAE_REST_SalvaScheda.setTestOrderItemAttributeValues(lavoro.Id, new Map<String, String>{
            'SIAE-ATTR-RADIOINSTORE' => '2',
            'SIAE-ATTR-PALINSESTO' => 'BD'
        });

        Test.startTest();
        SIAE_REST_SalvaScheda.SalvaSchedaBuildResult buildResult =
            SIAE_REST_SalvaScheda.buildRequestFromOrderItem(lavoro.Id);
        Test.stopTest();

        Integer strumentiRs = 0;
        String raggruppamento = null;
        String quantitaLuogoComune = null;

        for (SIAE_REST_SalvaScheda.Strumento strumento : buildResult.request.scheda.strumenti) {
            if (strumento.idStrumento != 'RS') { continue; }
            strumentiRs++;

            for (SIAE_REST_SalvaScheda.Parametro parametro : strumento.parametri) {
                if (parametro.nome == 'raggruppamento') { raggruppamento = parametro.valore; }
                if (parametro.nome == 'LC') { quantitaLuogoComune = parametro.valore; }
            }
        }

        System.assertEquals(
            1,
            strumentiRs,
            'Il palinsesto non deve generare uno strumento RS separato: deve confluire in quello della Radio in Store.'
        );
        System.assertEquals(
            'BD',
            raggruppamento,
            'Il parametro raggruppamento deve contenere il Value della picklist Palinsesto.'
        );
        System.assertEquals(
            '2',
            quantitaLuogoComune,
            'La quantita della Radio in Store deve restare invariata accanto al raggruppamento.'
        );
    }

    /**
     * Un attributo non numerico senza metadata STRUMENTO di tipo string non deve
     * generare parametri: viene solo tracciato come warning.
     */
    @IsTest
    static void strumento_valore_non_numerico_senza_metadata_string_ignorato() {
        OrderItem lavoro = getOrderItemByProductCode('SIAE-PROD-LAVORO');

        SIAE_REST_SalvaScheda.setTestOrderItemAttributeValues(lavoro.Id, new Map<String, String>{
            'SIAE-ATTR-RADIO' => '1',
            'SIAE-ATTR-TV-OVR40' => 'NON-NUMERICO'
        });

        Test.startTest();
        SIAE_REST_SalvaScheda.SalvaSchedaBuildResult buildResult =
            SIAE_REST_SalvaScheda.buildRequestFromOrderItem(lavoro.Id);
        Test.stopTest();

        Boolean hasWarning = false;
        for (String warning : buildResult.warnings) {
            if (warning.contains('SIAE-ATTR-TV-OVR40') && warning.contains('non numerico')) { hasWarning = true; }
        }
        System.assert(
            hasWarning,
            'Un valore non numerico senza metadata string deve produrre un warning esplicito.'
        );

        for (SIAE_REST_SalvaScheda.Strumento strumento : buildResult.request.scheda.strumenti) {
            for (SIAE_REST_SalvaScheda.Parametro parametro : strumento.parametri) {
                System.assertNotEquals(
                    'NON-NUMERICO',
                    parametro.valore,
                    'Un valore non numerico non deve finire nei parametri strumento.'
                );
            }
        }
    }

    /**
     * Crea al volo un OrderItem su un prodotto/genere arbitrario, per esercitare
     * la precedenza genere -> ALL dei SIAE_GenereLocaleParameter__mdt STRUMENTO.
     */
    private static OrderItem buildOrderItemForGenere(String productCode, String genereName) {
        Order ord = [SELECT Id FROM Order LIMIT 1];

        Product2 prod = new Product2(
            Name = 'Test ' + productCode,
            ProductCode = productCode,
            IsActive = true
        );
        putIfCreateable(prod, 'SIAE_IdTableDDA__c', 'DDA-' + genereName);
        putIfCreateable(prod, 'SIAE_IdTableDC__c', 'DC-' + genereName);
        insert prod;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = prod.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert pbe;

        OrderItem oi = buildGenericOrderItem(ord.Id, pbe.Id, 100, genereName, 100);
        insert oi;

        return oi;
    }

    private static SIAE_REST_SalvaScheda.Strumento getSingleStrumento(
        SIAE_REST_SalvaScheda.SalvaSchedaBuildResult buildResult,
        String idStrumento
    ) {
        SIAE_REST_SalvaScheda.Strumento found = null;
        Integer matches = 0;

        for (SIAE_REST_SalvaScheda.Strumento strumento : buildResult.request.scheda.strumenti) {
            if (strumento.idStrumento != idStrumento) { continue; }
            matches++;
            found = strumento;
        }

        System.assertEquals(
            1,
            matches,
            'Atteso un solo strumento con idStrumento ' + idStrumento + '.'
        );
        return found;
    }

    private static Map<String, String> parametriByNome(SIAE_REST_SalvaScheda.Strumento strumento) {
        Map<String, String> result = new Map<String, String>();
        for (SIAE_REST_SalvaScheda.Parametro parametro : strumento.parametri) {
            result.put(parametro.nome, parametro.valore);
        }
        return result;
    }

    /**
     * Licenze senza TV disponibili (Bar): SIAE-ATTR-VIDEO rappresenta il
     * televisore, quindi l'override per genere deve vincere sulla riga
     * GenereCode = ALL e mandare a SPORT idStrumento 5 invece di 7B.
     */
    @IsTest
    static void strumento_video_override_genere_bar_manda_televisore() {
        OrderItem bar = buildOrderItemForGenere('SIAE-PROD-BAR', 'Bar');

        SIAE_REST_SalvaScheda.setTestOrderItemAttributeValues(bar.Id, new Map<String, String>{
            'SIAE-ATTR-VIDEO' => '3'
        });

        Test.startTest();
        SIAE_REST_SalvaScheda.SalvaSchedaBuildResult buildResult =
            SIAE_REST_SalvaScheda.buildRequestFromOrderItem(bar.Id);
        Test.stopTest();

        System.assertEquals(
            '16',
            buildResult.resolvedGenereLocaleCode,
            'Genere 16 atteso per Bar/SIAE-PROD-BAR.'
        );

        for (SIAE_REST_SalvaScheda.Strumento strumento : buildResult.request.scheda.strumenti) {
            System.assertNotEquals(
                '7B',
                strumento.idStrumento,
                'Sul genere 16 l\'attributo Video non deve piu generare il Lettore VHS 7B.'
            );
        }

        Map<String, String> parametri = parametriByNome(getSingleStrumento(buildResult, '5'));

        System.assertEquals('3', parametri.get('LC'), 'La quantita Video deve arrivare come LC del Televisore.');
        System.assertEquals('Fino a 40', parametri.get('pollici'), 'Il Televisore deve portare il parametro pollici.');
    }

    /**
     * Sala Bingo espone sia Video sia Altoparlanti Video: entrambi mappano sul
     * Televisore con lo stesso valore di pollici, quindi devono confluire in un
     * unico elemento strumenti[] con LC e AS affiancati.
     */
    @IsTest
    static void strumento_video_e_altoparlanti_confluiscono_in_un_solo_televisore() {
        OrderItem bingo = buildOrderItemForGenere('SIAE-PROD-BINGO', 'Sala Bingo');

        SIAE_REST_SalvaScheda.setTestOrderItemAttributeValues(bingo.Id, new Map<String, String>{
            'SIAE-ATTR-VIDEO' => '2',
            'SIAE-ATTR-ALTOP-VIDEO' => '4'
        });

        Test.startTest();
        SIAE_REST_SalvaScheda.SalvaSchedaBuildResult buildResult =
            SIAE_REST_SalvaScheda.buildRequestFromOrderItem(bingo.Id);
        Test.stopTest();

        System.assertEquals(
            '21',
            buildResult.resolvedGenereLocaleCode,
            'Genere 21 atteso per Sala Bingo/SIAE-PROD-BINGO.'
        );

        System.assertEquals(
            1,
            buildResult.request.scheda.strumenti.size(),
            'Video e Altoparlanti Video sono lo stesso apparecchio: atteso un solo strumento.'
        );

        Map<String, String> parametri = parametriByNome(getSingleStrumento(buildResult, '5'));

        System.assertEquals('2', parametri.get('LC'), 'LC dal Video.');
        System.assertEquals('4', parametri.get('AS'), 'AS dagli Altoparlanti Video.');
        System.assertEquals('Fino a 40', parametri.get('pollici'), 'pollici condiviso dai due attributi.');
    }

    /**
     * Regressione: sui generi che espongono anche le TV, Video resta il lettore
     * VHS/DVD (7B) tramite il fallback su GenereCode = ALL.
     */
    @IsTest
    static void strumento_video_resta_lettore_vhs_sui_generi_fuori_scope() {
        OrderItem circolo = buildOrderItemForGenere('SIAE-PROD-CIRCOLI', 'Circolo');

        SIAE_REST_SalvaScheda.setTestOrderItemAttributeValues(circolo.Id, new Map<String, String>{
            'SIAE-ATTR-VIDEO' => '1'
        });

        Test.startTest();
        SIAE_REST_SalvaScheda.SalvaSchedaBuildResult buildResult =
            SIAE_REST_SalvaScheda.buildRequestFromOrderItem(circolo.Id);
        Test.stopTest();

        System.assertEquals(
            '10',
            buildResult.resolvedGenereLocaleCode,
            'Genere 10 atteso per Circolo/SIAE-PROD-CIRCOLI.'
        );

        for (SIAE_REST_SalvaScheda.Strumento strumento : buildResult.request.scheda.strumenti) {
            System.assertNotEquals(
                '5',
                strumento.idStrumento,
                'Sui generi fuori scope Video non deve diventare Televisore.'
            );
        }

        Map<String, String> parametri = parametriByNome(getSingleStrumento(buildResult, '7B'));
        System.assertEquals('1', parametri.get('LC'), 'La quantita Video deve restare LC del Lettore VHS.');
    }

    /**
     * Jukebox (idStrumento 6), Video jukebox (7A) e Karaoke (11) non prevedono
     * mai diritti connessi: in costiStrumenti[] l'elemento Jukebox deve avere
     * costiDc null (costiDda resta valorizzato), senza generare i parametri
     * mancanti costiDc.vociCosto[] / costiDc.idTabella. Radio Tradizionale (3)
     * della stessa licenza mantiene costiDc valorizzato.
     * Scenario: DirittiConnessi > 0, PaymentItem DDA su entrambi gli strumenti
     * e un solo PaymentItem DC non FLAT (0784 / LC) su Radio.
     */
    @IsTest
    static void costiStrumenti_jukebox_senza_dc_non_flat() {
        OrderItem lavoro = getOrderItemByProductCode('SIAE-PROD-LAVORO');

        OrderItem lavoroUpdate = new OrderItem(Id = lavoro.Id);
        putIfUpdateable(lavoroUpdate, 'SIAE_DirittiConnessi__c', 50);
        putIfUpdateable(lavoroUpdate, 'SIAE_PaymentItems__c', JSON.serialize(new Map<String, Object>{
            'paymentItems' => new List<Object>{
                new Map<String, Object>{
                    'itemCode' => '2216',
                    'amount' => '100.00',
                    'type' => 'DDA',
                    'revenueItemType' => 'LC',
                    'materialTaxClassification' => 'E',
                    'instrumentId' => '3'
                },
                new Map<String, Object>{
                    'itemCode' => '2216',
                    'amount' => '50.00',
                    'type' => 'DDA',
                    'revenueItemType' => 'LC',
                    'materialTaxClassification' => 'E',
                    'instrumentId' => '6'
                },
                new Map<String, Object>{
                    'itemCode' => '0784',
                    'amount' => '30.00',
                    'type' => 'DC',
                    'revenueItemType' => 'LC',
                    'materialTaxClassification' => 'E',
                    'instrumentId' => '3'
                }
            }
        }));
        update lavoroUpdate;

        // SIAE-ATTR-RADIO -> idStrumento 3, SIAE-ATTR-JUKEBOX -> idStrumento 6 (metadata GenereCode ALL, parametro LC).
        SIAE_REST_SalvaScheda.setTestOrderItemAttributeValues(lavoro.Id, new Map<String, String>{
            'SIAE-ATTR-RADIO' => '2',
            'SIAE-ATTR-JUKEBOX' => '1'
        });

        Test.startTest();
        SIAE_REST_SalvaScheda.SalvaSchedaBuildResult buildResult =
            SIAE_REST_SalvaScheda.buildRequestFromOrderItem(lavoro.Id);
        Test.stopTest();

        List<SIAE_REST_SalvaScheda.CostiStrumento> costiStrumenti = buildResult.request.tariffa.costiStrumenti;

        SIAE_REST_SalvaScheda.CostiStrumento costoJukebox = getCostiStrumentoById(costiStrumenti, '6');
        System.assertNotEquals(null, costoJukebox, 'Atteso elemento costiStrumenti[] per Jukebox (idStrumento 6).');
        System.assertNotEquals(null, costoJukebox.costiDda, 'Il Jukebox deve mantenere costiDda valorizzato.');
        System.assertEquals(null, costoJukebox.costiDc, 'Il Jukebox non prevede diritti connessi: costiDc deve essere null.');

        SIAE_REST_SalvaScheda.CostiStrumento costoRadio = getCostiStrumentoById(costiStrumenti, '3');
        System.assertNotEquals(null, costoRadio, 'Atteso elemento costiStrumenti[] per Radio Tradizionale (idStrumento 3).');
        System.assertNotEquals(null, costoRadio.costiDc, 'La Radio Tradizionale prevede diritti connessi: costiDc deve essere valorizzato.');
        System.assert(String.isNotBlank(costoRadio.costiDc.idTabella), 'costiDc.idTabella della Radio Tradizionale non deve essere vuoto.');

        SIAE_REST_SalvaScheda.VoceCosto voceDc = null;
        for (SIAE_REST_SalvaScheda.VoceCosto voce : costoRadio.costiDc.vociCosto) {
            if ('0784'.equals(voce.id)) { voceDc = voce; }
        }
        System.assertNotEquals(null, voceDc, 'Atteso costiDc.vociCosto[] della Radio con la voce 0784.');
        System.assertEquals(30.00, voceDc.importo, 'La voce 0784 deve avere l\'importo del PaymentItem DC (30.00).');

        for (String missing : buildResult.missingParameters) {
            System.assertEquals(
                false,
                missing.contains('costiDc'),
                'Nessun parametro mancante relativo a costiDc atteso per il Jukebox senza DC: ' + missing
            );
        }
    }

    /**
     * Stesso scenario con PaymentItem DC FLAT (0780 / FLAT, 80.00): il totale
     * FLAT e' "di scheda" ma non puo' finire su uno strumento senza DC. Il
     * Jukebox non riceve costiDc; l'importo reale va su Radio Tradizionale.
     *
     * Ordinamento scheda.strumenti[]: buildStrumentiFromAccumulators ordina gli
     * accumulatori per chiave testuale "idStrumento[|parametri fissi]", quindi
     * '3' (Radio) precede sempre '6' (Jukebox) e il Jukebox non puo' essere la
     * prima occorrenza con questa coppia di strumenti: l'ordine non e'
     * controllabile dal test. Con Radio prima, la regola "FLAT sulla prima
     * occorrenza" e la nuova regola "FLAT su uno strumento con DC" coincidono;
     * il test resta come guardia di regressione sul risultato atteso.
     */
    @IsTest
    static void costiStrumenti_jukebox_senza_dc_flat() {
        OrderItem lavoro = getOrderItemByProductCode('SIAE-PROD-LAVORO');

        OrderItem lavoroUpdate = new OrderItem(Id = lavoro.Id);
        putIfUpdateable(lavoroUpdate, 'SIAE_DirittiConnessi__c', 50);
        putIfUpdateable(lavoroUpdate, 'SIAE_PaymentItems__c', JSON.serialize(new Map<String, Object>{
            'paymentItems' => new List<Object>{
                new Map<String, Object>{
                    'itemCode' => '2216',
                    'amount' => '100.00',
                    'type' => 'DDA',
                    'revenueItemType' => 'LC',
                    'materialTaxClassification' => 'E',
                    'instrumentId' => '3'
                },
                new Map<String, Object>{
                    'itemCode' => '2216',
                    'amount' => '50.00',
                    'type' => 'DDA',
                    'revenueItemType' => 'LC',
                    'materialTaxClassification' => 'E',
                    'instrumentId' => '6'
                },
                new Map<String, Object>{
                    'itemCode' => '0780',
                    'amount' => '80.00',
                    'type' => 'DC',
                    'revenueItemType' => 'FLAT',
                    'materialTaxClassification' => 'E',
                    'instrumentId' => '3'
                }
            }
        }));
        update lavoroUpdate;

        SIAE_REST_SalvaScheda.setTestOrderItemAttributeValues(lavoro.Id, new Map<String, String>{
            'SIAE-ATTR-RADIO' => '2',
            'SIAE-ATTR-JUKEBOX' => '1'
        });

        Test.startTest();
        SIAE_REST_SalvaScheda.SalvaSchedaBuildResult buildResult =
            SIAE_REST_SalvaScheda.buildRequestFromOrderItem(lavoro.Id);
        Test.stopTest();

        List<SIAE_REST_SalvaScheda.CostiStrumento> costiStrumenti = buildResult.request.tariffa.costiStrumenti;

        SIAE_REST_SalvaScheda.CostiStrumento costoJukebox = getCostiStrumentoById(costiStrumenti, '6');
        System.assertNotEquals(null, costoJukebox, 'Atteso elemento costiStrumenti[] per Jukebox (idStrumento 6).');
        System.assertNotEquals(null, costoJukebox.costiDda, 'Il Jukebox deve mantenere costiDda valorizzato.');
        System.assertEquals(null, costoJukebox.costiDc, 'Il Jukebox non prevede diritti connessi: costiDc deve essere null anche con DC FLAT.');

        SIAE_REST_SalvaScheda.CostiStrumento costoRadio = getCostiStrumentoById(costiStrumenti, '3');
        System.assertNotEquals(null, costoRadio, 'Atteso elemento costiStrumenti[] per Radio Tradizionale (idStrumento 3).');
        System.assertNotEquals(null, costoRadio.costiDc, 'La Radio Tradizionale prevede diritti connessi: costiDc deve essere valorizzato.');

        SIAE_REST_SalvaScheda.VoceCosto voceFlat = null;
        for (SIAE_REST_SalvaScheda.VoceCosto voce : costoRadio.costiDc.vociCosto) {
            if ('0780'.equals(voce.id)) { voceFlat = voce; }
        }
        System.assertNotEquals(null, voceFlat, 'Atteso costiDc.vociCosto[] della Radio con la voce FLAT 0780.');
        System.assertEquals(80.00, voceFlat.importo, 'La voce FLAT 0780 deve avere l\'importo reale del PaymentItem DC (80.00) sulla Radio.');

        for (String missing : buildResult.missingParameters) {
            System.assertEquals(
                false,
                missing.contains('costiDc'),
                'Nessun parametro mancante relativo a costiDc atteso per il Jukebox senza DC: ' + missing
            );
        }
    }

    /**
     * Negozi sotto i 200 mq: le voci DC FLAT (0787/0788) vengono trattate per
     * strumento (tipo LC / Apparecchio) e non "di scheda". Uno strumento senza
     * alcun PaymentItem DC (qui Attese telefoniche, idStrumento 4) deve avere
     * costiDc null con costiDda valorizzato, senza parametri mancanti costiDc.
     * Scenario: DirittiConnessi > 0, SIAE-ATTR-QTA = 150 (< 200),
     * SIAE-ATTR-RADIO -> idStrumento 3 e SIAE-ATTR-ATTESE-TEL -> idStrumento 4
     * (metadata GenereCode ALL: nessuna riga STRUMENTO specifica per il genere
     * 06 Negozio), PaymentItem DDA su 3 e 4, PaymentItem DC FLAT solo su 3.
     */
    @IsTest
    static void costiStrumenti_negozi_sotto_soglia_strumento_senza_dc() {
        OrderItem negozi = buildNegoziOrderItemWithDcFlatItems(150);

        Id negoziProductId = [
            SELECT PricebookEntry.Product2Id
            FROM OrderItem
            WHERE Id = :negozi.Id
            LIMIT 1
        ].PricebookEntry.Product2Id;

        Product2 negoziProductUpdate = new Product2(Id = negoziProductId);
        putIfUpdateable(negoziProductUpdate, 'SIAE_IdTableDDA__c', 'DDA-NEG');
        putIfUpdateable(negoziProductUpdate, 'SIAE_IdTableDC__c', 'DC-NEG');
        update negoziProductUpdate;

        OrderItem negoziUpdate = new OrderItem(Id = negozi.Id);
        putIfUpdateable(negoziUpdate, 'SIAE_DirittiConnessi__c', 70);
        putIfUpdateable(negoziUpdate, 'SIAE_PaymentItems__c', JSON.serialize(new Map<String, Object>{
            'paymentItems' => new List<Object>{
                new Map<String, Object>{
                    'itemCode' => '2216',
                    'amount' => '100.00',
                    'type' => 'DDA',
                    'revenueItemType' => 'LC',
                    'materialTaxClassification' => 'E',
                    'instrumentId' => '3'
                },
                new Map<String, Object>{
                    'itemCode' => '2216',
                    'amount' => '60.00',
                    'type' => 'DDA',
                    'revenueItemType' => 'LC',
                    'materialTaxClassification' => 'E',
                    'instrumentId' => '4'
                },
                new Map<String, Object>{
                    'itemCode' => '0787',
                    'amount' => '45.50',
                    'type' => 'DC',
                    'revenueItemType' => 'FLAT',
                    'materialTaxClassification' => 'E',
                    'instrumentId' => '3'
                },
                new Map<String, Object>{
                    'itemCode' => '0788',
                    'amount' => '24.50',
                    'type' => 'DC',
                    'revenueItemType' => 'FLAT',
                    'materialTaxClassification' => 'E',
                    'instrumentId' => '3'
                }
            }
        }));
        update negoziUpdate;

        // SIAE-ATTR-RADIO -> idStrumento 3, SIAE-ATTR-ATTESE-TEL -> idStrumento 4 (metadata GenereCode ALL); QTA resta sotto soglia.
        SIAE_REST_SalvaScheda.setTestOrderItemAttributeValues(negozi.Id, new Map<String, String>{
            'SIAE-ATTR-QTA' => '150',
            'SIAE-ATTR-RADIO' => '2',
            'SIAE-ATTR-ATTESE-TEL' => '1'
        });

        Test.startTest();
        SIAE_REST_SalvaScheda.SalvaSchedaBuildResult buildResult =
            SIAE_REST_SalvaScheda.buildRequestFromOrderItem(negozi.Id);
        Test.stopTest();

        List<SIAE_REST_SalvaScheda.CostiStrumento> costiStrumenti = buildResult.request.tariffa.costiStrumenti;

        SIAE_REST_SalvaScheda.CostiStrumento costoAttese = getCostiStrumentoById(costiStrumenti, '4');
        System.assertNotEquals(null, costoAttese, 'Atteso elemento costiStrumenti[] per Attese telefoniche (idStrumento 4).');
        System.assertNotEquals(null, costoAttese.costiDda, 'Le Attese telefoniche devono mantenere costiDda valorizzato.');
        System.assertEquals(
            null,
            costoAttese.costiDc,
            'Nessun PaymentItem DC per l\'idStrumento 4: costiDc deve essere null, non un dettaglio vuoto.'
        );

        SIAE_REST_SalvaScheda.CostiStrumento costoRadio = getCostiStrumentoById(costiStrumenti, '3');
        System.assertNotEquals(null, costoRadio, 'Atteso elemento costiStrumenti[] per Radio Tradizionale (idStrumento 3).');
        System.assertNotEquals(null, costoRadio.costiDc, 'La Radio Tradizionale ha i PaymentItem DC: costiDc deve essere valorizzato.');

        SIAE_REST_SalvaScheda.VoceCosto voce0787 = null;
        SIAE_REST_SalvaScheda.VoceCosto voce0788 = null;
        for (SIAE_REST_SalvaScheda.VoceCosto voce : costoRadio.costiDc.vociCosto) {
            if ('0787'.equals(voce.id)) { voce0787 = voce; }
            if ('0788'.equals(voce.id)) { voce0788 = voce; }
        }
        System.assertNotEquals(null, voce0787, 'Atteso costiDc.vociCosto[] della Radio con la voce 0787.');
        System.assertNotEquals(null, voce0788, 'Atteso costiDc.vociCosto[] della Radio con la voce 0788.');
        System.assertEquals(45.50, voce0787.importo, 'La voce 0787 deve avere l\'importo del PaymentItem DC (45.50).');
        System.assertEquals(24.50, voce0788.importo, 'La voce 0788 deve avere l\'importo del PaymentItem DC (24.50).');

        for (String missing : buildResult.missingParameters) {
            System.assertEquals(
                false,
                missing.contains('costiDc'),
                'Nessun parametro mancante relativo a costiDc atteso per uno strumento Negozi senza DC: ' + missing
            );
        }
    }

    /**
     * Licenza con diritti connessi (DirittiConnessi > 0) ma pricing senza alcun
     * PaymentItem DC: la request non e' completa e missingParameters deve
     * segnalare almeno una voce relativa a costiDc.
     * Scenario: SIAE-PROD-LAVORO, SIAE-ATTR-RADIO -> idStrumento 3 (metadata
     * GenereCode ALL), solo PaymentItem DDA su idStrumento 3.
     */
    @IsTest
    static void costiStrumenti_dc_previsti_senza_payment_item_dc_incompleta() {
        OrderItem lavoro = getOrderItemByProductCode('SIAE-PROD-LAVORO');

        OrderItem lavoroUpdate = new OrderItem(Id = lavoro.Id);
        putIfUpdateable(lavoroUpdate, 'SIAE_DirittiConnessi__c', 50);
        putIfUpdateable(lavoroUpdate, 'SIAE_PaymentItems__c', JSON.serialize(new Map<String, Object>{
            'paymentItems' => new List<Object>{
                new Map<String, Object>{
                    'itemCode' => '2216',
                    'amount' => '100.00',
                    'type' => 'DDA',
                    'revenueItemType' => 'LC',
                    'materialTaxClassification' => 'E',
                    'instrumentId' => '3'
                }
            }
        }));
        update lavoroUpdate;

        SIAE_REST_SalvaScheda.setTestOrderItemAttributeValues(lavoro.Id, new Map<String, String>{
            'SIAE-ATTR-RADIO' => '2'
        });

        Test.startTest();
        SIAE_REST_SalvaScheda.SalvaSchedaBuildResult buildResult =
            SIAE_REST_SalvaScheda.buildRequestFromOrderItem(lavoro.Id);
        Test.stopTest();

        Boolean hasMissingCostiDc = false;
        for (String missing : buildResult.missingParameters) {
            if (missing.contains('costiDc')) { hasMissingCostiDc = true; }
        }
        System.assertEquals(
            true,
            hasMissingCostiDc,
            'Con diritti connessi previsti e nessun PaymentItem DC valido la request non e\' completa: atteso almeno un parametro mancante costiDc. missingParameters: ' + String.join(buildResult.missingParameters, '; ')
        );
    }

    /**
     * Negozi sopra i 200 mq (nessun override Apparecchio/LC): le voci DC FLAT
     * 0787/0788 sono "di scheda". L'importo reale va sulla prima occorrenza di
     * scheda.strumenti[] (Radio Tradizionale, idStrumento 3, che precede il
     * Televisore 5 nell'ordinamento per chiave), mentre il Televisore "Fino a 40"
     * pollici (idStrumento 5) deve comunque avere costiDc con le stesse voci a
     * importo 0 e tipoPagamento FLAT.
     * Scenario: DirittiConnessi > 0, SIAE-ATTR-QTA = 220 (> 200),
     * SIAE-ATTR-RADIO -> idStrumento 3 e SIAE-ATTR-TV-UND40 -> idStrumento 5 con
     * parametro pollici "Fino a 40" (metadata GenereCode ALL: nessuna riga
     * STRUMENTO specifica per il genere 06 Negozio), PaymentItem DDA LC su 3
     * (2231) e su 5 (2216), PaymentItem DC FLAT 0787/0788 con instrumentId 3.
     */
    @IsTest
    static void costiStrumenti_negozi_sopra_soglia_flat_placeholder_su_tv() {
        Decimal importoDc0787 = 80.25;
        Decimal importoDc0788 = 35.75;

        OrderItem negozi = buildNegoziOrderItemWithDcFlatItems(220);

        Id negoziProductId = [
            SELECT PricebookEntry.Product2Id
            FROM OrderItem
            WHERE Id = :negozi.Id
            LIMIT 1
        ].PricebookEntry.Product2Id;

        Product2 negoziProductUpdate = new Product2(Id = negoziProductId);
        putIfUpdateable(negoziProductUpdate, 'SIAE_IdTableDDA__c', 'DDA-NEG');
        putIfUpdateable(negoziProductUpdate, 'SIAE_IdTableDC__c', 'DC-NEG');
        update negoziProductUpdate;

        OrderItem negoziUpdate = new OrderItem(Id = negozi.Id);
        putIfUpdateable(negoziUpdate, 'SIAE_DirittiConnessi__c', importoDc0787 + importoDc0788);
        putIfUpdateable(negoziUpdate, 'SIAE_PaymentItems__c', JSON.serialize(new Map<String, Object>{
            'paymentItems' => new List<Object>{
                new Map<String, Object>{
                    'itemCode' => '2231',
                    'amount' => '100.00',
                    'type' => 'DDA',
                    'revenueItemType' => 'LC',
                    'materialTaxClassification' => 'E',
                    'instrumentId' => '3'
                },
                new Map<String, Object>{
                    'itemCode' => '2216',
                    'amount' => '60.00',
                    'type' => 'DDA',
                    'revenueItemType' => 'LC',
                    'materialTaxClassification' => 'E',
                    'instrumentId' => '5'
                },
                new Map<String, Object>{
                    'itemCode' => '0787',
                    'amount' => String.valueOf(importoDc0787),
                    'type' => 'DC',
                    'revenueItemType' => 'FLAT',
                    'materialTaxClassification' => 'E',
                    'instrumentId' => '3'
                },
                new Map<String, Object>{
                    'itemCode' => '0788',
                    'amount' => String.valueOf(importoDc0788),
                    'type' => 'DC',
                    'revenueItemType' => 'FLAT',
                    'materialTaxClassification' => 'E',
                    'instrumentId' => '3'
                }
            }
        }));
        update negoziUpdate;

        // SIAE-ATTR-RADIO -> idStrumento 3, SIAE-ATTR-TV-UND40 -> idStrumento 5 (pollici "Fino a 40"), metadata GenereCode ALL; QTA sopra soglia.
        SIAE_REST_SalvaScheda.setTestOrderItemAttributeValues(negozi.Id, new Map<String, String>{
            'SIAE-ATTR-QTA' => '220',
            'SIAE-ATTR-RADIO' => '1',
            'SIAE-ATTR-TV-UND40' => '1'
        });

        Test.startTest();
        SIAE_REST_SalvaScheda.SalvaSchedaBuildResult buildResult =
            SIAE_REST_SalvaScheda.buildRequestFromOrderItem(negozi.Id);
        Test.stopTest();

        List<SIAE_REST_SalvaScheda.CostiStrumento> costiStrumenti = buildResult.request.tariffa.costiStrumenti;

        SIAE_REST_SalvaScheda.CostiStrumento costoRadio = getCostiStrumentoById(costiStrumenti, '3');
        System.assertNotEquals(null, costoRadio, 'Atteso elemento costiStrumenti[] per Radio Tradizionale (idStrumento 3).');
        System.assertNotEquals(null, costoRadio.costiDc, 'La Radio Tradizionale e\' la prima occorrenza: costiDc deve essere valorizzato.');
        System.assertEquals(
            TIPO_PAGAMENTO_FLAT_EXPECTED,
            costoRadio.costiDc.tipoPagamento,
            'Sopra i 200 mq il costiDc della Radio deve avere tipoPagamento FLAT.'
        );

        SIAE_REST_SalvaScheda.VoceCosto radioVoce0787 = null;
        SIAE_REST_SalvaScheda.VoceCosto radioVoce0788 = null;
        for (SIAE_REST_SalvaScheda.VoceCosto voce : costoRadio.costiDc.vociCosto) {
            if ('0787'.equals(voce.id)) { radioVoce0787 = voce; }
            if ('0788'.equals(voce.id)) { radioVoce0788 = voce; }
        }
        System.assertNotEquals(null, radioVoce0787, 'Atteso costiDc.vociCosto[] della Radio con la voce 0787.');
        System.assertNotEquals(null, radioVoce0788, 'Atteso costiDc.vociCosto[] della Radio con la voce 0788.');
        System.assertEquals(importoDc0787, radioVoce0787.importo, 'La voce 0787 della Radio deve avere l\'importo del PaymentItem DC FLAT di input.');
        System.assertEquals(importoDc0788, radioVoce0788.importo, 'La voce 0788 della Radio deve avere l\'importo del PaymentItem DC FLAT di input.');

        SIAE_REST_SalvaScheda.CostiStrumento costoTv = getCostiStrumentoById(costiStrumenti, '5');
        System.assertNotEquals(null, costoTv, 'Atteso elemento costiStrumenti[] per Televisore "Fino a 40" (idStrumento 5).');
        System.assertNotEquals(null, costoTv.costiDc, 'Il Televisore deve avere costiDc valorizzato con le voci DC FLAT a importo 0.');
        System.assertEquals(
            TIPO_PAGAMENTO_FLAT_EXPECTED,
            costoTv.costiDc.tipoPagamento,
            'Il costiDc del Televisore deve avere tipoPagamento FLAT.'
        );

        SIAE_REST_SalvaScheda.VoceCosto tvVoce0787 = null;
        SIAE_REST_SalvaScheda.VoceCosto tvVoce0788 = null;
        for (SIAE_REST_SalvaScheda.VoceCosto voce : costoTv.costiDc.vociCosto) {
            if ('0787'.equals(voce.id)) { tvVoce0787 = voce; }
            if ('0788'.equals(voce.id)) { tvVoce0788 = voce; }
        }
        System.assertNotEquals(null, tvVoce0787, 'Atteso costiDc.vociCosto[] del Televisore con la voce 0787.');
        System.assertNotEquals(null, tvVoce0788, 'Atteso costiDc.vociCosto[] del Televisore con la voce 0788.');
        System.assertEquals(0, tvVoce0787.importo, 'La voce 0787 del Televisore deve essere un placeholder a importo 0.');
        System.assertEquals(0, tvVoce0788.importo, 'La voce 0788 del Televisore deve essere un placeholder a importo 0.');

        for (String missing : buildResult.missingParameters) {
            System.assertEquals(
                false,
                missing.contains('costiDc'),
                'Nessun parametro mancante relativo a costiDc atteso per Negozi sopra soglia con DC FLAT: ' + missing
            );
        }
    }

    @IsTest
    static void testParsePaymentWrapper_StringAndNumericAmounts() {
        PricingPaymentItem.Wrapper wrapper = SIAE_REST_SalvaScheda.parsePaymentWrapper(
            '{"paymentItems":[' +
                '{"itemCode":"T2216","amount":"16.00","type":"DDA","instrumentId":"I-1","attributeCode":"SIAE-ATTR-RADIO"},' +
                '{"itemCode":"0787","amount":5.25,"type":"DC","incidencePercentage":40}' +
            ']}'
        );

        System.assertEquals(2, wrapper.paymentItems.size(), 'Attesi due paymentItems.');
        PricingPaymentItem dda = wrapper.paymentItems[0];
        System.assertEquals('T2216', dda.itemCode);
        System.assertEquals('16.00', dda.amount, 'L importo MdA resta String.');
        System.assertEquals('DDA', dda.type);
        System.assertEquals('I-1', dda.instrumentId);
        System.assertEquals('SIAE-ATTR-RADIO', dda.attributeCode);

        PricingPaymentItem dc = wrapper.paymentItems[1];
        System.assertEquals('5.25', dc.amount, 'L importo numerico viene normalizzato a String.');
        System.assertEquals(40, dc.incidencePercentage);
    }

    @IsTest
    static void testParsePaymentWrapper_MissingItemsAndNullRoot() {
        System.assertEquals(null, SIAE_REST_SalvaScheda.parsePaymentWrapper('null'), 'JSON null deve dare wrapper nullo.');

        PricingPaymentItem.Wrapper wrapper = SIAE_REST_SalvaScheda.parsePaymentWrapper('{}');
        System.assertNotEquals(null, wrapper);
        System.assertEquals(null, wrapper.paymentItems, 'Senza paymentItems la lista resta nulla, come con JSON.deserialize.');
    }

}