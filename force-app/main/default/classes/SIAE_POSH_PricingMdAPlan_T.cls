/**
 * @description       : Classe di test per SIAE_POSH_PricingMdAPlan
 * @author            : Domenico Del Prete - domenico.delprete@nttdata.com
 * @group             : NTT Data
 * @last modified on  : 05-27-2026
 * @last modified by  : Gaetano Iuliano - gaetano.iuliano@nttdata.com
**/
@IsTest
private class SIAE_POSH_PricingMdAPlan_T {

    private class MockIndustriesContextAdapter implements RCAContextGateway {
        public Map<String, Object> queryResponse = new Map<String, Object>();
        public Map<String, Object> verifyResponse = new Map<String, Object>();
        public Map<String, Object> lastUpdateInput;
        public Integer queryCallCount = 0;
        public Boolean updateCalled = false;

        public Map<String, Object> queryTags(Map<String, Object> input) {
            queryCallCount++;
            Map<String, Object> res = (queryCallCount == 1) ? queryResponse : (verifyResponse != null ? verifyResponse : queryResponse);
            return res != null ? res : new Map<String, Object>();
        }

        public void updateContextAttributes(Map<String, Object> input) {
            updateCalled = true;
            lastUpdateInput = input;
        }
    }

    @TestSetup
    static void setup() {
        Product2 prod = new Product2(Name = 'Test Product', Family = 'Musica d\'ambiente', ProductCode = 'SIAE-PROD-TEST', IsActive = true);
        Product2 prodAffitti = new Product2(Name = 'Affitti Brevi', Family = 'Musica d\'ambiente', ProductCode = 'SIAE-PROD-AFFITTI-BREVI', IsActive = true);
        insert new List<Product2>{prod, prodAffitti};

        Account acc = new Account(Name = 'Test Account', SIAE_TaxClassification__c = 'IVA_22');
        insert acc;

        // Creazione Quote senza Opportunity usando QuoteAccountId come indicato
        Quote q = new Quote(Name = 'Test Quote', Pricebook2Id = Test.getStandardPricebookId());
        q.put('QuoteAccountId', acc.Id); 
        insert q;

        Order o = new Order(AccountId = acc.Id, Status = 'Draft', EffectiveDate = Date.today(), Pricebook2Id = Test.getStandardPricebookId());
        insert o;

        SObject accordo = (SObject) Type.forName('SIAE_AccordoCommerciale__c').newInstance();
        accordo.put('SIAE_CodiceAccordoCommerciale__c', 'ACAI');
        safePut(accordo, 'SIAE_GruppoDiSconti__c', 'Musica d\'ambiente');
        safePut(accordo, 'SIAE_ScontoAC__c', '10');
        insert accordo;
    }

    private static void safePut(SObject obj, String fieldName, Object value) {
        if (obj.getSObjectType().getDescribe().fields.getMap().containsKey(fieldName)) {
            obj.put(fieldName, value);
        }
    }

    @IsTest
    static void testExecuteInternal_MissingContextId() {
        MockIndustriesContextAdapter mockCtx = new MockIndustriesContextAdapter();
        SIAE_POSH_PricingMdAPlan.ProcessResult res = SIAE_POSH_PricingMdAPlan.executeInternal('', mockCtx);
        System.assertEquals('Missing ctxInstanceId.', res.message);
    }

    @IsTest
    static void testExecuteInternal_NoItemsFound() {
        MockIndustriesContextAdapter mockCtx = new MockIndustriesContextAdapter();
        mockCtx.queryResponse = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItem' => new List<Object>()
            }
        };
        SIAE_POSH_PricingMdAPlan.ProcessResult res = SIAE_POSH_PricingMdAPlan.executeInternal('CTX-001', mockCtx);
        System.assertEquals('No SalesTransactionItem found.', res.message);
    }

    @IsTest
    static void testExecuteInternal_Success() {
        Product2 prod = [SELECT Id FROM Product2 LIMIT 1];
        Map<String, Object> item1 = new Map<String, Object>{
            'dataPath' => new List<Object>{ 'CTX-001', 'Order', 'item1' },
            'tagValue' => new Map<String, Object>{
                'LineItem' => new Map<String, Object>{ 'tagValue' => 'item1' },
                'Product' => new Map<String, Object>{ 'tagValue' => prod.Id },
                'ItemNetTotalPrice' => new Map<String, Object>{ 'tagValue' => 100.0 }
            }
        };
        MockIndustriesContextAdapter mockCtx = new MockIndustriesContextAdapter();
        mockCtx.queryResponse = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItem' => new List<Object>{ item1 },
                'SalesTransactionItemAttribute' => new List<Object>()
            }
        };
        SIAE_POSH_PricingMdAPlan.ProcessResult res = SIAE_POSH_PricingMdAPlan.executeInternal('CTX-001', mockCtx);
        System.assertNotEquals(null, res.message);
    }

    @IsTest
    static void testExecuteInternal_ProRataAnnuale_NotReappliedOnAnnualCoverage() {
        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'SIAE-PROD-TEST' LIMIT 1];
        Map<String, Object> item1 = new Map<String, Object>{
            'dataPath' => new List<Object>{ 'CTX-PRORATA', 'Order', 'item1' },
            'tagValue' => new Map<String, Object>{
                'LineItem' => new Map<String, Object>{ 'tagValue' => 'item1' },
                'Product' => new Map<String, Object>{ 'tagValue' => prod.Id },
                'ItemNetTotalPrice' => new Map<String, Object>{ 'tagValue' => 120.0 },
                'SIAE_TypeOfCoverage__c' => new Map<String, Object>{ 'tagValue' => 'Annuale' },
                'EffectiveFrom' => new Map<String, Object>{ 'tagValue' => Date.newInstance(2026, 7, 1) }
            }
        };
        MockIndustriesContextAdapter mockCtx = new MockIndustriesContextAdapter();
        mockCtx.queryResponse = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItem' => new List<Object>{ item1 },
                'SalesTransactionItemAttribute' => new List<Object>()
            }
        };

        Test.startTest();
        SIAE_POSH_PricingMdAPlan.executeInternal('CTX-PRORATA', mockCtx);
        Test.stopTest();

        Decimal totalDA = extractAttributeValue(mockCtx.lastUpdateInput, 'SIAE_TotalDA__c');
        System.assertEquals(
            120.00,
            totalDA,
            'Il pro-rata annuale e applicato a monte (SIAE_POSH_PricingMdAFlow): il Plan non deve riapplicarlo, 120 resta 120'
        );
    }

    @IsTest
    static void testExecuteInternal_ProRataAnnuale_SkippedOnNonAnnualCoverage() {
        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'SIAE-PROD-TEST' LIMIT 1];
        Map<String, Object> item1 = new Map<String, Object>{
            'dataPath' => new List<Object>{ 'CTX-PRORATA-SEM', 'Order', 'item1' },
            'tagValue' => new Map<String, Object>{
                'LineItem' => new Map<String, Object>{ 'tagValue' => 'item1' },
                'Product' => new Map<String, Object>{ 'tagValue' => prod.Id },
                'ItemNetTotalPrice' => new Map<String, Object>{ 'tagValue' => 120.0 },
                'SIAE_TypeOfCoverage__c' => new Map<String, Object>{ 'tagValue' => 'Semestrale' },
                'EffectiveFrom' => new Map<String, Object>{ 'tagValue' => Date.newInstance(2026, 7, 1) }
            }
        };
        MockIndustriesContextAdapter mockCtx = new MockIndustriesContextAdapter();
        mockCtx.queryResponse = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItem' => new List<Object>{ item1 },
                'SalesTransactionItemAttribute' => new List<Object>()
            }
        };

        Test.startTest();
        SIAE_POSH_PricingMdAPlan.executeInternal('CTX-PRORATA-SEM', mockCtx);
        Test.stopTest();

        Decimal totalDA = extractAttributeValue(mockCtx.lastUpdateInput, 'SIAE_TotalDA__c');
        System.assertEquals(
            120.00,
            totalDA,
            'Copertura non-Annuale gia stagionalizzata dal motore: nessuna pro-rata, 120 invariato'
        );
    }

    @IsTest
    static void testCoverageMethods() {
        // Test sumPaymentItemAmounts con formati diversi (copre righe 445-460)
        PricingPaymentItem pi1 = new PricingPaymentItem();
        pi1.amount = '1.200,50';
        PricingPaymentItem pi2 = new PricingPaymentItem();
        pi2.amount = '300,00';
        MdAPricingProcessor.sumPaymentItemAmounts(new List<PricingPaymentItem>{pi1, pi2});
        
        RCAContextReader.parse(new Map<String, Object>{
            'SalesTransactionItem' => new List<Object>{
                new Map<String, Object>{
                    'dataPath' => new List<Object>{'ctx', 'quote', 'line1'}, 
                    'tagValue' => new Map<String, Object>{
                        'LineItem' => new Map<String, Object>{'tagValue' => 'line1'},
                        // Copre isNodeDeleted
                        'DUMMY' => new Map<String, Object>{'dmlStatus' => 'DELETED'}
                    }
                }
            }
        });
    }

    @IsTest
    static void testSumPaymentItemAmountsByType() {
        PricingPaymentItem siDda = new PricingPaymentItem();
        siDda.type = 'SI_DDA';
        siDda.amount = '3,00';

        PricingPaymentItem siDc = new PricingPaymentItem();
        siDc.type = 'SI_DC';
        siDc.amount = '1,00';

        PricingPaymentItem dda = new PricingPaymentItem();
        dda.type = 'DDA';
        dda.amount = '100,00';

        List<PricingPaymentItem> items =
            new List<PricingPaymentItem>{ siDda, siDc, dda };

        System.assertEquals(
            3.00,
            MdAPricingProcessor.sumPaymentItemAmountsByType(items, 'SI_DDA'),
            'Deve sommare solo le voci SI_DDA'
        );
        System.assertEquals(
            1.00,
            MdAPricingProcessor.sumPaymentItemAmountsByType(items, 'SI_DC'),
            'Deve sommare solo le voci SI_DC'
        );
        System.assertEquals(
            0,
            MdAPricingProcessor.sumPaymentItemAmountsByType(items, 'SI_QA'),
            'Tipo assente deve dare 0'
        );
        System.assertEquals(
            0,
            MdAPricingProcessor.sumPaymentItemAmountsByType(null, 'SI_DDA'),
            'Lista nulla deve dare 0'
        );
        System.assertEquals(
            0,
            MdAPricingProcessor.sumPaymentItemAmountsByType(items, null),
            'FeeType nullo deve dare 0'
        );
    }

    @IsTest
    static void testExecuteInternal_TotaloneRicostruitoDaiSottocampi() {
        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'SIAE-PROD-TEST' LIMIT 1];
        Map<String, Object> item1 = new Map<String, Object>{
            'dataPath' => new List<Object>{ 'CTX-TOTALONE', 'Order', 'item1' },
            'tagValue' => new Map<String, Object>{
                'LineItem' => new Map<String, Object>{ 'tagValue' => 'item1' },
                'Product' => new Map<String, Object>{ 'tagValue' => prod.Id },
                'ItemNetTotalPrice' => new Map<String, Object>{ 'tagValue' => 100.0 }
            }
        };
        MockIndustriesContextAdapter mockCtx = new MockIndustriesContextAdapter();
        mockCtx.queryResponse = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItem' => new List<Object>{ item1 },
                'SalesTransactionItemAttribute' => new List<Object>()
            }
        };

        Test.startTest();
        SIAE_POSH_PricingMdAPlan.executeInternal('CTX-TOTALONE', mockCtx);
        Test.stopTest();

        Decimal totalDA = extractAttributeValue(mockCtx.lastUpdateInput, 'SIAE_TotalDA__c');
        Decimal netTotalPrice = extractAttributeValue(mockCtx.lastUpdateInput, 'NetTotalPrice');

        System.assertEquals(100.00, totalDA, 'TotalDA base senza istruttoria (nessun record SI seminato)');
        System.assertEquals(
            totalDA,
            netTotalPrice,
            'Il totalone deve essere ricostruito dai sotto-campi: senza DC, NetTotalPrice == TotalDA'
        );
    }

    @IsTest
    static void testExecuteInternal_DirittiConnessi_WrittenAsZero_WhenProductHasNoDCConfig() {
        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'SIAE-PROD-TEST' LIMIT 1];
        Map<String, Object> item1 = new Map<String, Object>{
            'dataPath' => new List<Object>{ 'CTX-NODC', 'Order', 'item1' },
            'tagValue' => new Map<String, Object>{
                'LineItem' => new Map<String, Object>{ 'tagValue' => 'item1' },
                'Product' => new Map<String, Object>{ 'tagValue' => prod.Id },
                'ItemNetTotalPrice' => new Map<String, Object>{ 'tagValue' => 100.0 }
            }
        };
        MockIndustriesContextAdapter mockCtx = new MockIndustriesContextAdapter();
        mockCtx.queryResponse = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItem' => new List<Object>{ item1 },
                'SalesTransactionItemAttribute' => new List<Object>()
            }
        };

        Test.startTest();
        SIAE_POSH_PricingMdAPlan.executeInternal('CTX-NODC', mockCtx);
        Test.stopTest();

        Decimal dirittiConnessi = extractAttributeValue(mockCtx.lastUpdateInput, 'SIAE_DirittiConnessi__c');
        System.assertNotEquals(
            null,
            dirittiConnessi,
            'Licenza senza DC applicabile (nessuna SIAE_DirittiConnessiConfig__mdt per il ProductCode): il campo deve essere ' +
            'comunque scritto esplicitamente a 0, mai lasciato blank, altrimenti SIAE_REST_SalvaScheda fallisce su tariffa.dc mancante.'
        );
        System.assertEquals(
            0.00,
            dirittiConnessi,
            'Nessun Diritto Connesso applicabile per questo prodotto: atteso 0, non blank.'
        );
    }

    @IsTest
    static void testIndustriesContextAdapter_Coverage() {
        try {
            SIAE_POSH_PricingMdAPlan.executeWithContextId('test-ctx-id');
        } catch (Exception e) {}
    }

    @IsTest
    static void testExecute_NullRequestReturnsMissingContext() {
        RevSignaling.TransactionResponse response = new SIAE_POSH_PricingMdAPlan().execute(null);
        System.assertEquals(RevSignaling.TransactionStatus.SUCCESS, response.status);
        System.assertEquals('Missing ctxInstanceId.', response.message);
    }

    @IsTest
    static void testExecuteInternal_NoUpdatableNodes() {
        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'SIAE-PROD-TEST' LIMIT 1];
        // Senza dataPath il writer non può indirizzare il nodo: nessun update verso il context.
        Map<String, Object> item1 = new Map<String, Object>{
            'tagValue' => new Map<String, Object>{
                'LineItem' => new Map<String, Object>{ 'tagValue' => 'item1' },
                'Product' => new Map<String, Object>{ 'tagValue' => prod.Id },
                'ItemNetTotalPrice' => new Map<String, Object>{ 'tagValue' => 100.0 }
            }
        };
        MockIndustriesContextAdapter mockCtx = new MockIndustriesContextAdapter();
        mockCtx.queryResponse = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItem' => new List<Object>{ item1 },
                'SalesTransactionItemAttribute' => new List<Object>()
            }
        };

        SIAE_POSH_PricingMdAPlan.ProcessResult res = SIAE_POSH_PricingMdAPlan.executeInternal('CTX-NOPATH', mockCtx);

        System.assertEquals('No pricing attributes updated.', res.message);
        System.assertEquals(false, mockCtx.updateCalled, 'Il context non deve essere aggiornato');
    }

    @IsTest
    static void testAffittiBrevi_Coverage() {
        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'SIAE-PROD-AFFITTI-BREVI' LIMIT 1];
        
        Map<String, Object> item = new Map<String, Object>{
            'dataPath' => new List<Object>{ 'CTX', 'Order', 'lineAB' },
            'tagValue' => new Map<String, Object>{
                'LineItem' => new Map<String, Object>{ 'tagValue' => 'lineAB' },
                'Product' => new Map<String, Object>{ 'tagValue' => prod.Id },
                'ItemNetTotalPrice' => new Map<String, Object>{ 'tagValue' => 200.0 }
            }
        };
        
        // Mock degli attributi per forzare i rami logici di classifyAffittiBrevi (> 25 qta)
        List<Object> attributes = new List<Object>{
            createAttr('SIAE-ATTR-QTA', '30'),
            createAttr('SIAE-ATTR-RADIO', '1')
        };

        MockIndustriesContextAdapter mockCtx = new MockIndustriesContextAdapter();
        mockCtx.queryResponse = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItem' => new List<Object>{ item },
                'SalesTransactionItemAttribute' => attributes
            }
        };
        
        Test.startTest();
        SIAE_POSH_PricingMdAPlan.executeInternal('CTX-AFFITTI', mockCtx);
        Test.stopTest();
    }

    private static Map<String, Object> createAttr(String code, String val) {
        return new Map<String, Object>{
            'dataPath' => new List<Object>{ 'CTX', 'Order', 'item1' },
            'tagValue' => new Map<String, Object>{
                'AttributeDefinitionCode' => new Map<String, Object>{ 'tagValue' => code },
                'AttributeValue' => new Map<String, Object>{ 'tagValue' => val }
            }
        };
    }

    @IsTest
    static void testExecuteInternal_CommercialAgreementQuotaAddedToTotalDA() {
        Product2 prod = new Product2(
            Name = 'Prodotto Accordo Commerciale',
            Family = 'AA',
            ProductCode = 'SIAE-PROD-QUOTA-TEST',
            IsActive = true
        );
        insert prod;

        SIAE_AccordoCommerciale__c accordo = new SIAE_AccordoCommerciale__c(
            SIAE_CodiceAccordoCommerciale__c = 'ACAI',
            SIAE_CodiceDiIncrocio__c = 'AA',
            SIAE_RiduzioneCompensoBase__c = 0,
            SIAE_VoceQuota__c = 'QA-TEST',
            SIAE_QuotaUnitaria__c = 5
        );
        insert accordo;

        Map<String, Object> item1 = new Map<String, Object>{
            'dataPath' => new List<Object>{ 'CTX-QUOTA', 'Order', 'item1' },
            'tagValue' => new Map<String, Object>{
                'LineItem' => new Map<String, Object>{ 'tagValue' => 'item1' },
                'Product' => new Map<String, Object>{ 'tagValue' => prod.Id },
                'ItemNetTotalPrice' => new Map<String, Object>{ 'tagValue' => 100.0 },
                'SIAE_CommercialAgreementCode__c' => new Map<String, Object>{ 'tagValue' => 'ACAI' }
            }
        };

        List<Object> attributes = new List<Object>{
            createAttr('SIAE-ATTR-RADIO', '2')
        };

        MockIndustriesContextAdapter mockCtx = new MockIndustriesContextAdapter();
        mockCtx.queryResponse = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItem' => new List<Object>{ item1 },
                'SalesTransactionItemAttribute' => attributes
            }
        };

        Test.startTest();
        SIAE_POSH_PricingMdAPlan.executeInternal('CTX-QUOTA', mockCtx);
        Test.stopTest();

        System.assertEquals(true, mockCtx.updateCalled, 'Deve aggiornare il context');

        Decimal totalDA = extractAttributeValue(mockCtx.lastUpdateInput, 'SIAE_TotalDA__c');
        System.assertEquals(
            110.00,
            totalDA,
            'SIAE_TotalDA__c deve includere la quota (5 x 2 dispositivi = 10) sommata al compenso scontato (100)'
        );

        Decimal totalCommercialAgreement = extractAttributeValue(mockCtx.lastUpdateInput, 'SIAE_TotalCommercialAgreement__c');
        System.assertEquals(
            10.00,
            totalCommercialAgreement,
            'SIAE_TotalCommercialAgreement__c deve continuare a riportare la quota separatamente'
        );
    }

    private static Decimal extractAttributeValue(Map<String, Object> updateInput, String attributeName) {
        List<Object> nodePathAndAttributes = (List<Object>) updateInput.get('nodePathAndAttributes');
        for (Object rawNode : nodePathAndAttributes) {
            Map<String, Object> node = (Map<String, Object>) rawNode;
            List<Object> attrs = (List<Object>) node.get('attributes');
            for (Object rawAttr : attrs) {
                Map<String, Object> attr = (Map<String, Object>) rawAttr;
                if (attributeName.equals(attr.get('attributeName'))) {
                    return (Decimal) attr.get('attributeValue');
                }
            }
        }
        return null;
    }

    @IsTest
    static void testFlatTotalDA_AudioWithAdditionalAFlatDevice() {
        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'SIAE-PROD-TEST' LIMIT 1];

        RCASalesTransaction.ItemNode node =
            new RCASalesTransaction.ItemNode();

        node.productId = String.valueOf(prod.Id);
        node.lineItemId = 'line-flat-total';
        node.typeOfFlatRate = 'FLAT_AUDIO';
        node.flatAudioAmount = 384.60;
        node.netTotalPrice = 724.54;
        node.coeffMaggiorazioneMQ = 1.10;
        node.coeffAreeEsterne = 1;
        node.periodicityCoefficient = 1;

        node.attributes = new List<RCASalesTransaction.AttributeNode>{
            createSalesItemAttr('SIAE-ATTR-JUKEBOX', '1', '110.35'),
            createSalesItemAttr('SIAE-ATTR-RADIO', '2', '288.09'),
            createSalesItemAttr('SIAE-ATTR-AUDIO', '1', '326.10')
        };

        SIAE_ConfigurazionePricing__c conf = new SIAE_ConfigurazionePricing__c(
            SIAE_AggiungiAFLAT__c = 'SIAE-ATTR-JUKEBOX;SIAE-ATTR-KARAOKE;SIAE-ATTR-VIDEO-JUKEBOX'
        );

        Decimal totalDa = MdAPricingProcessor.calculateTotalDA(
            node,
            new Map<String, SIAE_ConfigurazionePricing__c>{
                String.valueOf(prod.Id) => conf
            }
        );

        System.assertEquals(
            533.41,
            totalDa.setScale(2),
            'La flat audio deve applicare i coefficienti alla base flat e sommare solo gli apparecchi A-FLAT'
        );
    }

    @IsTest
    static void testFlatTotalDA_TrimestraleDoesNotRestagionalizeAFlatDevice() {
        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'SIAE-PROD-TEST' LIMIT 1];

        RCASalesTransaction.ItemNode node =
            new RCASalesTransaction.ItemNode();

        node.productId = String.valueOf(prod.Id);
        node.lineItemId = 'line-flat-seasonal';
        node.typeOfFlatRate = 'FLAT_AUDIO';
        node.flatAudioAmount = 163.95;
        node.coeffMaggiorazioneMQ = 1;
        node.coeffAreeEsterne = 1;
        node.periodicityCoefficient = 0.4;

        node.attributes = new List<RCASalesTransaction.AttributeNode>{
            createSalesItemAttr('SIAE-ATTR-JUKEBOX', '1', '44.14'),
            createSalesItemAttr('SIAE-ATTR-RADIO', '2', '42.88')
        };

        SIAE_ConfigurazionePricing__c conf = new SIAE_ConfigurazionePricing__c(
            SIAE_AggiungiAFLAT__c = 'SIAE-ATTR-JUKEBOX'
        );

        Decimal totalDa = MdAPricingProcessor.calculateTotalDA(
            node,
            new Map<String, SIAE_ConfigurazionePricing__c>{
                String.valueOf(prod.Id) => conf
            }
        );

        System.assertEquals(
            109.72,
            totalDa.setScale(2),
            'Il deviceTotalPrice A-FLAT è già stagionalizzato e non deve essere moltiplicato di nuovo'
        );
    }

    @IsTest
    static void testResolveFlatBaseAmountAndAdditionalFlatDeviceAmount() {
        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'SIAE-PROD-TEST' LIMIT 1];

        RCASalesTransaction.ItemNode audioNode =
            new RCASalesTransaction.ItemNode();

        audioNode.productId = String.valueOf(prod.Id);
        audioNode.typeOfFlatRate = 'FLAT_AUDIO';
        audioNode.flatAudioAmount = 100;
        audioNode.flatVideoAmount = 200;
        audioNode.netTotalPrice = 300;
        audioNode.attributes = new List<RCASalesTransaction.AttributeNode>{
            createSalesItemAttr('SIAE-ATTR-JUKEBOX', '1', '50'),
            createSalesItemAttr('SIAE-ATTR-RADIO', '1', '80')
        };

        RCASalesTransaction.ItemNode videoNode =
            new RCASalesTransaction.ItemNode();

        videoNode.typeOfFlatRate = 'FLAT_AUDIO_VIDEO';
        videoNode.flatAudioAmount = 100;
        videoNode.flatVideoAmount = 200;
        videoNode.netTotalPrice = 300;

        RCASalesTransaction.ItemNode nonFlatNode =
            new RCASalesTransaction.ItemNode();

        nonFlatNode.netTotalPrice = 300;

        System.assertEquals(100, MdAPricingProcessor.resolveFlatBaseAmount(audioNode), 'Base FLAT_AUDIO errata');
        System.assertEquals(200, MdAPricingProcessor.resolveFlatBaseAmount(videoNode), 'Base FLAT_AUDIO_VIDEO errata');
        System.assertEquals(300, MdAPricingProcessor.resolveFlatBaseAmount(nonFlatNode), 'Base non-flat errata');

        SIAE_ConfigurazionePricing__c conf = new SIAE_ConfigurazionePricing__c(
            SIAE_AggiungiAFLAT__c = 'SIAE-ATTR-JUKEBOX'
        );

        Decimal additionalAmount = MdAPricingProcessor.calculateAdditionalFlatDeviceAmount(
            audioNode,
            new Map<String, SIAE_ConfigurazionePricing__c>{
                String.valueOf(prod.Id) => conf
            }
        );

        System.assertEquals(
            50.00,
            additionalAmount.setScale(2),
            'Deve sommare solo gli attributi presenti in SIAE_AggiungiAFLAT__c'
        );
    }

    @IsTest
    static void testParseQueryResult_FlatFieldsTransactionAndDeviceTotalPrice() {
        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'SIAE-PROD-TEST' LIMIT 1];

        Map<String, Object> queryRes = new Map<String, Object>{
            'SalesTransaction' => new List<Object>{
                new Map<String, Object>{
                    'dataPath' => new List<Object>{ 'CTX', 'TX-1' },
                    'tagValue' => new Map<String, Object>{
                        'Name' => new Map<String, Object>{ 'tagValue' => 'Transaction 1' }
                    }
                }
            },
            'SalesTransactionItem' => new List<Object>{
                new Map<String, Object>{
                    'dataPath' => new List<Object>{ 'CTX', 'TX-1', 'LINE-PATH-1' },
                    'tagValue' => new Map<String, Object>{
                        'LineItem' => new Map<String, Object>{ 'tagValue' => 'line-flat' },
                        'Product' => new Map<String, Object>{ 'tagValue' => prod.Id },
                        'ItemNetTotalPrice' => new Map<String, Object>{ 'tagValue' => 100 },
                        'SIAE_TypeOfFlatRate__c' => new Map<String, Object>{ 'tagValue' => 'FLAT_AUDIO' },
                        'SIAE_FlatAudio__c' => new Map<String, Object>{ 'tagValue' => 384.60 },
                        'SIAE_FlatVideo__c' => new Map<String, Object>{ 'tagValue' => 885.75 },
                        'SIAE_CoeffMaggiorazioneMQ__c' => new Map<String, Object>{ 'tagValue' => 1.1 },
                        'SIAE_CoeffAreeEsterne__c' => new Map<String, Object>{ 'tagValue' => 1 },
                        'SIAE_CoeffStagionalita__c' => new Map<String, Object>{ 'tagValue' => 0.4 }
                    }
                }
            },
            'SalesTransactionItemAttribute' => new List<Object>{
                new Map<String, Object>{
                    'dataPath' => new List<Object>{ 'CTX', 'TX-1', 'LINE-PATH-1', 'ATTR-1' },
                    'tagValue' => new Map<String, Object>{
                        'AttributeDefinitionCode' => new Map<String, Object>{ 'tagValue' => 'SIAE-ATTR-JUKEBOX' },
                        'AttributeValue' => new Map<String, Object>{ 'tagValue' => '1' },
                        'SIAE_DevicePrice' => new Map<String, Object>{ 'tagValue' => '110.35' },
                        'SIAE_DeviceTotalPrice' => new Map<String, Object>{ 'tagValue' => '44.14' }
                    }
                }
            }
        };

        RCASalesTransaction parsed =
            RCAContextReader.parse(queryRes);

        System.assertEquals(1, parsed.transactions.size(), 'Transaction non parsata');
        System.assertEquals('TX-1', parsed.transactions[0].transactionKey, 'Transaction key errata');

        System.assertEquals(1, parsed.items.size(), 'Item non parsato');
        RCASalesTransaction.ItemNode item = parsed.items[0];

        System.assertEquals('FLAT_AUDIO', item.typeOfFlatRate, 'TypeOfFlatRate non parsato');
        System.assertEquals(384.60, item.flatAudioAmount, 'Flat audio non parsata');
        System.assertEquals(885.75, item.flatVideoAmount, 'Flat video non parsata');
        System.assertEquals(1.1, item.coeffMaggiorazioneMQ, 'Coeff MQ non parsato');
        System.assertEquals(1, item.coeffAreeEsterne, 'Coeff aree esterne non parsato');
        System.assertEquals(0.4, item.periodicityCoefficient, 'Coeff stagionalità non parsato');

        System.assertEquals(1, item.attributes.size(), 'Attributo non associato alla riga');
        System.assertEquals('SIAE-ATTR-JUKEBOX', item.attributes[0].attributeCode, 'Attribute code errato');
        System.assertEquals('44.14', String.valueOf(item.attributes[0].deviceTotalPrice), 'DeviceTotalPrice non parsato');
        System.assertEquals('1', item.attributeValueByCode.get('SIAE-ATTR-JUKEBOX'), 'attributeValueByCode non popolata');
    }

    @IsTest
    static void testParseQueryResult_PicklistAttributeResolution() {
        // Picklist di attributo con un valore risolvibile
        AttributePicklist picklist = new AttributePicklist(Name = 'Test Classificazione');
        insert picklist;

        AttributePicklistValue pv = new AttributePicklistValue(
            Name = 'Capelli ed estetica',
            PicklistId = picklist.Id,
            Code = 'CAP-EST-TEST',
            Value = 'Capelli ed estetica'
        );
        insert pv;

        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'SIAE-PROD-TEST' LIMIT 1];

        Map<String, Object> queryRes = new Map<String, Object>{
            'SalesTransactionItem' => new List<Object>{
                new Map<String, Object>{
                    'dataPath' => new List<Object>{ 'CTX', 'TX-1', 'LINE-1' },
                    'tagValue' => new Map<String, Object>{
                        'LineItem' => new Map<String, Object>{ 'tagValue' => 'line-1' },
                        'Product' => new Map<String, Object>{ 'tagValue' => prod.Id }
                    }
                }
            },
            'SalesTransactionItemAttribute' => new List<Object>{
                // Attributo Picklist: solo l'Id del valore, senza AttributeValue testuale
                new Map<String, Object>{
                    'dataPath' => new List<Object>{ 'CTX', 'TX-1', 'LINE-1', 'ATTR-CLASS' },
                    'tagValue' => new Map<String, Object>{
                        'AttributeDefinitionCode' => new Map<String, Object>{ 'tagValue' => 'SIAE-ATTR-CLASS' },
                        'AttributePicklistValue' => new Map<String, Object>{ 'tagValue' => pv.Id }
                    }
                },
                // Attributo Number classico: AttributeValue testuale presente
                new Map<String, Object>{
                    'dataPath' => new List<Object>{ 'CTX', 'TX-1', 'LINE-1', 'ATTR-QTA' },
                    'tagValue' => new Map<String, Object>{
                        'AttributeDefinitionCode' => new Map<String, Object>{ 'tagValue' => 'SIAE-ATTR-QTA' },
                        'AttributeValue' => new Map<String, Object>{ 'tagValue' => '100' }
                    }
                },
                // Attributo Picklist con Id malformato: il cast fallisce -> deve essere scartato
                new Map<String, Object>{
                    'dataPath' => new List<Object>{ 'CTX', 'TX-1', 'LINE-1', 'ATTR-FAKE' },
                    'tagValue' => new Map<String, Object>{
                        'AttributeDefinitionCode' => new Map<String, Object>{ 'tagValue' => 'SIAE-ATTR-FAKE' },
                        'AttributePicklistValue' => new Map<String, Object>{ 'tagValue' => 'INVALID_PICKLIST_ID' }
                    }
                }
            }
        };

        Test.startTest();
        RCASalesTransaction parsed =
            RCAContextReader.parse(queryRes);
        Test.stopTest();

        System.assertEquals(1, parsed.items.size(), 'Item non parsato');
        RCASalesTransaction.ItemNode item = parsed.items[0];

        // Il picklist deve essere risolto nel suo Value testuale
        System.assertEquals(
            'Capelli ed estetica',
            item.attributeValueByCode.get('SIAE-ATTR-CLASS'),
            'Il valore del picklist deve essere risolto e messo in attributeValueByCode'
        );
        // L'attributo Number resta invariato
        System.assertEquals(
            '100',
            item.attributeValueByCode.get('SIAE-ATTR-QTA'),
            'QTA non parsato'
        );
        // Il picklist non risolvibile non deve comparire
        System.assertEquals(
            false,
            item.attributeValueByCode.containsKey('SIAE-ATTR-FAKE'),
            'Picklist non risolvibile deve essere scartato'
        );

        // Copertura diretta helper resolvePicklistValues
        System.assertEquals(
            0,
            RCAContextReader.resolvePicklistValues(null).size(),
            'Set nullo deve restituire mappa vuota'
        );
        System.assertEquals(
            'Capelli ed estetica',
            RCAContextReader.resolvePicklistValues(new Set<Id>{ pv.Id }).get(pv.Id),
            'resolvePicklistValues deve risolvere l Id nel Value'
        );
    }

    @IsTest
    static void testApplyStandardItemTotalsHasFlatAndTransactionTotals() {
        RCASalesTransaction.ItemNode flatNode =
            new RCASalesTransaction.ItemNode();

        flatNode.lineItemId = 'line-flat';
        flatNode.transactionKey = 'TX-1';
        flatNode.typeOfFlatRate = 'FLAT_AUDIO';

        MdAPricingProcessor.applyStandardItemTotals(flatNode, 533.414);

        System.assertEquals(533.41, flatNode.netTotalPrice, 'NetTotalPrice non aggiornato');
        System.assertEquals(533.41, flatNode.attributeToUpdate.get('NetTotalPrice'), 'NetTotalPrice update mancante');
        System.assertEquals(533.41, flatNode.attributeToUpdate.get('TotalLineAmount'), 'TotalLineAmount update mancante');

        RCASalesTransaction.ItemNode secondNode =
            new RCASalesTransaction.ItemNode();

        secondNode.lineItemId = 'line-normal';
        secondNode.transactionKey = 'TX-1';
        secondNode.netTotalPrice = 100;

        System.assertEquals(
            true,
            MdAPricingProcessor.hasAnyFlatRateSelected(
                new List<RCASalesTransaction.ItemNode>{ flatNode, secondNode }
            ),
            'Deve rilevare almeno una riga flat'
        );

        RCASalesTransaction ctxResult =
            new RCASalesTransaction();

        RCASalesTransaction.TransactionNode tx =
            new RCASalesTransaction.TransactionNode();

        tx.transactionKey = 'TX-1';
        tx.dataPath = new List<Object>{ 'CTX', 'TX-1' };

        ctxResult.transactions.add(tx);
        ctxResult.items.add(flatNode);
        ctxResult.items.add(secondNode);

        MdAPricingProcessor.addSalesTransactionStandardTotalUpdates(ctxResult);

        System.assertEquals(633.41, tx.attributeToUpdate.get('Subtotal'), 'Subtotal transazione errato');
        System.assertEquals(633.41, tx.attributeToUpdate.get('TotalAmount'), 'TotalAmount transazione errato');
    }

    @IsTest
    static void testProcess_NullOrEmptyTransactionIsNoOp() {
        MdAPricingProcessor.process(null);

        RCASalesTransaction emptyTransaction = new RCASalesTransaction();
        MdAPricingProcessor.process(emptyTransaction);

        System.assertEquals(
            0,
            RCAContextWriter.buildUpdates(emptyTransaction).size(),
            'Senza righe il processor non deve produrre update'
        );
    }

    @IsTest
    static void testBuildFlatCalculationSourceItemAndLoadFlatConfigurationsEmptyInputs() {
        RCASalesTransaction.ItemNode node =
            new RCASalesTransaction.ItemNode();

        node.attributes = new List<RCASalesTransaction.AttributeNode>{
            createSalesItemAttr('SIAE-ATTR-JUKEBOX', '1', '110.35')
        };

        Map<String, Object> sourceItem =
            MdAPricingProcessor.buildFlatCalculationSourceItem(node);

        List<Object> attrs = (List<Object>) sourceItem.get('SalesTransactionItemAttribute');
        System.assertEquals(1, attrs.size(), 'Source item flat deve contenere un attributo');

        Map<String, Object> attrNode = (Map<String, Object>) attrs[0];
        System.assertEquals('SIAE-ATTR-JUKEBOX', attrNode.get('AttributeDefinitionCode'), 'AttributeDefinitionCode errato');
        System.assertEquals('1', attrNode.get('AttributeValue'), 'AttributeValue errato');
        System.assertEquals('110.35', attrNode.get('SIAE_DeviceTotalPrice'), 'DeviceTotalPrice errato');

        System.assertEquals(
            0,
            MdAPricingProcessor.loadActiveFlatConfigurations(null).size(),
            'Null productIds deve restituire mappa vuota'
        );

        System.assertEquals(
            0,
            MdAPricingProcessor.loadActiveFlatConfigurations(new Set<String>{ 'not-an-id' }).size(),
            'ProductId non valido deve essere ignorato'
        );
    }

    private static RCASalesTransaction.AttributeNode createSalesItemAttr(
        String code,
        String value,
        Object deviceTotalPrice
    ) {
        RCASalesTransaction.AttributeNode attr =
            new RCASalesTransaction.AttributeNode();

        attr.attributeCode = code;
        attr.attributeValue = value;
        attr.deviceTotalPrice = deviceTotalPrice;

        return attr;
    }

    private static String resolveByAttributeRuleType() {
        for (Schema.PicklistEntry entry : SIAE_RegolaVoceIncasso__c.SIAE_RuleType__c.getDescribe().getPicklistValues()) {
            if (entry.isActive() && entry.getValue().toUpperCase().contains('ATTRIB')) {
                return entry.getValue();
            }
        }
        return null;
    }

    private static String extractPaymentItemsJson(Map<String, Object> updateInput) {
        List<Object> nodePathAndAttributes = (List<Object>) updateInput.get('nodePathAndAttributes');
        for (Object rawNode : nodePathAndAttributes) {
            Map<String, Object> node = (Map<String, Object>) rawNode;
            List<Object> attrs = (List<Object>) node.get('attributes');
            for (Object rawAttr : attrs) {
                Map<String, Object> attr = (Map<String, Object>) rawAttr;
                if ('SIAE_PaymentItems__c'.equals(attr.get('attributeName'))) {
                    return (String) attr.get('attributeValue');
                }
            }
        }
        return null;
    }

    private static PricingPaymentItem findPaymentItemByCode(
        PricingPaymentItem.Wrapper wrapper,
        String type,
        String itemCode
    ) {
        if (wrapper == null || wrapper.paymentItems == null) {
            return null;
        }
        for (PricingPaymentItem item : wrapper.paymentItems) {
            if (item != null && type == item.type && itemCode == item.itemCode) {
                return item;
            }
        }
        return null;
    }

    // PricingPaymentItem.amount è Object: JSON.deserialize tipizzato non è supportato.
    private static PricingPaymentItem.Wrapper parsePaymentWrapper(String paymentItemsJson) {
        PricingPaymentItem.Wrapper wrapper = new PricingPaymentItem.Wrapper();
        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(paymentItemsJson);
        for (Object raw : (List<Object>) root.get('paymentItems')) {
            Map<String, Object> itemMap = (Map<String, Object>) raw;
            PricingPaymentItem item = new PricingPaymentItem();
            item.itemCode = (String) itemMap.get('itemCode');
            item.type = (String) itemMap.get('type');
            item.amount = itemMap.get('amount') == null ? null : String.valueOf(itemMap.get('amount'));
            wrapper.paymentItems.add(item);
        }
        return wrapper;
    }

    @IsTest
    static void testExecuteInternal_DdaPaymentItemDiscountedByCommercialAgreement() {
        String byAttributeRuleType = resolveByAttributeRuleType();

        Product2 prod = new Product2(
            Name = 'Prodotto Sconto DDA',
            Family = 'AA',
            ProductCode = 'SIAE-PROD-DDA-DISCOUNT-TEST',
            IsActive = true
        );
        insert prod;

        SIAE_AccordoCommerciale__c accordo = new SIAE_AccordoCommerciale__c(
            SIAE_CodiceAccordoCommerciale__c = 'ACAI',
            SIAE_CodiceDiIncrocio__c = 'AA',
            SIAE_RiduzioneCompensoBase__c = 0.20
        );
        insert accordo;

        SIAE_VoceIncasso__c revenueItem = new SIAE_VoceIncasso__c(
            Name = 'DDA - T2216 - TEST',
            SIAE_Active__c = true,
            SIAE_Code__c = 'T2216',
            SIAE_ExternalId__c = 'TEST-REV-DDA-DISCOUNT',
            SIAE_FeeType__c = 'DDA'
        );
        insert revenueItem;

        SIAE_RegolaVoceIncasso__c rule = new SIAE_RegolaVoceIncasso__c(
            Name = 'DDA - BY ATTRIBUTE - TEST DISCOUNT',
            SIAE_Active__c = true,
            SIAE_ExternalId__c = 'TEST-RULE-DDA-DISCOUNT',
            SIAE_Priority__c = 1,
            SIAE_Product2__c = prod.Id,
            SIAE_FeeType__c = 'DDA',
            SIAE_RuleType__c = byAttributeRuleType
        );
        insert rule;

        SIAE_RegolaVoceIncassoAttributo__c ruleItem = new SIAE_RegolaVoceIncassoAttributo__c(
            Name = 'TEST-RITEM-DDA-DISCOUNT',
            SIAE_Active__c = true,
            SIAE_ExternalId__c = 'TEST-RITEM-DDA-DISCOUNT',
            SIAE_RevenueItemRule__c = rule.Id,
            SIAE_RevenueItem__c = revenueItem.Id,
            SIAE_AttributeCode__c = 'SIAE-ATTR-RADIO',
            SIAE_Required__c = true,
            SIAE_MinQuantity__c = 1
        );
        insert ruleItem;

        Map<String, Object> item1 = new Map<String, Object>{
            'dataPath' => new List<Object>{ 'CTX-DDA-DISC', 'Order', 'item1' },
            'tagValue' => new Map<String, Object>{
                'LineItem' => new Map<String, Object>{ 'tagValue' => 'item1' },
                'Product' => new Map<String, Object>{ 'tagValue' => prod.Id },
                'ItemNetTotalPrice' => new Map<String, Object>{ 'tagValue' => 100.0 },
                'SIAE_CommercialAgreementCode__c' => new Map<String, Object>{ 'tagValue' => 'ACAI' }
            }
        };

        List<Object> attributes = new List<Object>{
            createAttr('SIAE-ATTR-RADIO', '2')
        };
        // createAttr (già esistente in questa classe) non imposta deviceTotalPrice: lo aggiungiamo qui.
        Map<String, Object> radioAttrTag = (Map<String, Object>) ((Map<String, Object>) attributes[0]).get('tagValue');
        radioAttrTag.put('SIAE_DeviceTotalPrice', new Map<String, Object>{ 'tagValue' => '20' });

        MockIndustriesContextAdapter mockCtx = new MockIndustriesContextAdapter();
        mockCtx.queryResponse = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItem' => new List<Object>{ item1 },
                'SalesTransactionItemAttribute' => attributes
            }
        };

        Test.startTest();
        SIAE_POSH_PricingMdAPlan.executeInternal('CTX-DDA-DISC', mockCtx);
        Test.stopTest();

        System.assertEquals(true, mockCtx.updateCalled, 'Deve aggiornare il context');

        String paymentItemsJson = extractPaymentItemsJson(mockCtx.lastUpdateInput);
        System.assertNotEquals(null, paymentItemsJson, 'SIAE_PaymentItems__c deve essere valorizzato');

        PricingPaymentItem.Wrapper wrapper = parsePaymentWrapper(paymentItemsJson);

        PricingPaymentItem ddaItem = findPaymentItemByCode(wrapper, 'DDA', 'T2216');
        System.assertNotEquals(null, ddaItem, 'PaymentItem DDA T2216 deve essere presente');
        System.assertEquals(
            '16.00',
            ddaItem.amount,
            'PaymentItem DDA da 20.00 con sconto 20% deve diventare 16.00'
        );
    }

    @IsTest
    static void testExecuteInternal_DdaPaymentItemUnchangedWithoutCommercialAgreement() {
        String byAttributeRuleType = resolveByAttributeRuleType();

        Product2 prod = new Product2(
            Name = 'Prodotto Senza Accordo',
            Family = 'BB',
            ProductCode = 'SIAE-PROD-DDA-NOAGREEMENT-TEST',
            IsActive = true
        );
        insert prod;

        SIAE_VoceIncasso__c revenueItem = new SIAE_VoceIncasso__c(
            Name = 'DDA - T2216 - TEST NOAGREEMENT',
            SIAE_Active__c = true,
            SIAE_Code__c = 'T2216',
            SIAE_ExternalId__c = 'TEST-REV-DDA-NOAGREEMENT',
            SIAE_FeeType__c = 'DDA'
        );
        insert revenueItem;

        SIAE_RegolaVoceIncasso__c rule = new SIAE_RegolaVoceIncasso__c(
            Name = 'DDA - BY ATTRIBUTE - TEST NOAGREEMENT',
            SIAE_Active__c = true,
            SIAE_ExternalId__c = 'TEST-RULE-DDA-NOAGREEMENT',
            SIAE_Priority__c = 1,
            SIAE_Product2__c = prod.Id,
            SIAE_FeeType__c = 'DDA',
            SIAE_RuleType__c = byAttributeRuleType
        );
        insert rule;

        SIAE_RegolaVoceIncassoAttributo__c ruleItem = new SIAE_RegolaVoceIncassoAttributo__c(
            Name = 'TEST-RITEM-DDA-NOAGREEMENT',
            SIAE_Active__c = true,
            SIAE_ExternalId__c = 'TEST-RITEM-DDA-NOAGREEMENT',
            SIAE_RevenueItemRule__c = rule.Id,
            SIAE_RevenueItem__c = revenueItem.Id,
            SIAE_AttributeCode__c = 'SIAE-ATTR-RADIO',
            SIAE_Required__c = true,
            SIAE_MinQuantity__c = 1
        );
        insert ruleItem;

        // Nessun SIAE_CommercialAgreementCode__c: nessun accordo commerciale coinvolto.
        Map<String, Object> item1 = new Map<String, Object>{
            'dataPath' => new List<Object>{ 'CTX-DDA-NOAGREEMENT', 'Order', 'item1' },
            'tagValue' => new Map<String, Object>{
                'LineItem' => new Map<String, Object>{ 'tagValue' => 'item1' },
                'Product' => new Map<String, Object>{ 'tagValue' => prod.Id },
                'ItemNetTotalPrice' => new Map<String, Object>{ 'tagValue' => 100.0 }
            }
        };

        List<Object> attributes = new List<Object>{
            createAttr('SIAE-ATTR-RADIO', '2')
        };
        Map<String, Object> radioAttrTag = (Map<String, Object>) ((Map<String, Object>) attributes[0]).get('tagValue');
        radioAttrTag.put('SIAE_DeviceTotalPrice', new Map<String, Object>{ 'tagValue' => '20' });

        MockIndustriesContextAdapter mockCtx = new MockIndustriesContextAdapter();
        mockCtx.queryResponse = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItem' => new List<Object>{ item1 },
                'SalesTransactionItemAttribute' => attributes
            }
        };

        Test.startTest();
        SIAE_POSH_PricingMdAPlan.executeInternal('CTX-DDA-NOAGREEMENT', mockCtx);
        Test.stopTest();

        String paymentItemsJson = extractPaymentItemsJson(mockCtx.lastUpdateInput);
        PricingPaymentItem.Wrapper wrapper = parsePaymentWrapper(paymentItemsJson);

        PricingPaymentItem ddaItem = findPaymentItemByCode(wrapper, 'DDA', 'T2216');
        System.assertNotEquals(null, ddaItem, 'PaymentItem DDA T2216 deve essere presente');
        System.assertEquals(
            '20.00',
            ddaItem.amount,
            'Senza accordo commerciale, il PaymentItem DDA non deve essere scontato'
        );
    }

    private static Boolean isActiveFeeType(String feeType) {
        for (Schema.PicklistEntry entry : SIAE_VoceIncasso__c.SIAE_FeeType__c.getDescribe().getPicklistValues()) {
            if (entry.isActive() && entry.getValue() == feeType) {
                return true;
            }
        }
        return false;
    }

    @IsTest
    static void testExecuteInternal_FullDiscountStillGeneratesSiDda() {
        if (!isActiveFeeType('SI_DDA')) {
            return;
        }

        String byAttributeRuleType = resolveByAttributeRuleType();

        Product2 prod = new Product2(
            Name = 'Prodotto Sconto Totale',
            Family = 'CC',
            ProductCode = 'SIAE-PROD-DDA-FULLDISCOUNT-TEST',
            IsActive = true
        );
        insert prod;

        SIAE_AccordoCommerciale__c accordo = new SIAE_AccordoCommerciale__c(
            SIAE_CodiceAccordoCommerciale__c = 'ACAI',
            SIAE_CodiceDiIncrocio__c = 'CC',
            SIAE_RiduzioneCompensoBase__c = 1
        );
        insert accordo;

        SIAE_VoceIncasso__c revenueItem = new SIAE_VoceIncasso__c(
            Name = 'DDA - T2216 - TEST FULLDISCOUNT',
            SIAE_Active__c = true,
            SIAE_Code__c = 'T2216',
            SIAE_ExternalId__c = 'TEST-REV-DDA-FULLDISCOUNT',
            SIAE_FeeType__c = 'DDA'
        );
        insert revenueItem;

        SIAE_VoceIncasso__c siDdaRevenueItem = new SIAE_VoceIncasso__c(
            Name = 'SI_DDA - SD3760 - TEST FULLDISCOUNT',
            SIAE_Active__c = true,
            SIAE_Code__c = 'SD3760',
            SIAE_ExternalId__c = 'TEST-REV-SIDDA-FULLDISCOUNT',
            SIAE_FeeType__c = 'SI_DDA',
            SIAE_Amount__c = '3'
        );
        insert siDdaRevenueItem;

        SIAE_RegolaVoceIncasso__c rule = new SIAE_RegolaVoceIncasso__c(
            Name = 'DDA - BY ATTRIBUTE - TEST FULLDISCOUNT',
            SIAE_Active__c = true,
            SIAE_ExternalId__c = 'TEST-RULE-DDA-FULLDISCOUNT',
            SIAE_Priority__c = 1,
            SIAE_Product2__c = prod.Id,
            SIAE_FeeType__c = 'DDA',
            SIAE_RuleType__c = byAttributeRuleType
        );
        insert rule;

        SIAE_RegolaVoceIncassoAttributo__c ruleItem = new SIAE_RegolaVoceIncassoAttributo__c(
            Name = 'TEST-RITEM-DDA-FULLDISCOUNT',
            SIAE_Active__c = true,
            SIAE_ExternalId__c = 'TEST-RITEM-DDA-FULLDISCOUNT',
            SIAE_RevenueItemRule__c = rule.Id,
            SIAE_RevenueItem__c = revenueItem.Id,
            SIAE_AttributeCode__c = 'SIAE-ATTR-RADIO',
            SIAE_Required__c = true,
            SIAE_MinQuantity__c = 1
        );
        insert ruleItem;

        Map<String, Object> item1 = new Map<String, Object>{
            'dataPath' => new List<Object>{ 'CTX-DDA-FULLDISCOUNT', 'Order', 'item1' },
            'tagValue' => new Map<String, Object>{
                'LineItem' => new Map<String, Object>{ 'tagValue' => 'item1' },
                'Product' => new Map<String, Object>{ 'tagValue' => prod.Id },
                'ItemNetTotalPrice' => new Map<String, Object>{ 'tagValue' => 100.0 },
                'SIAE_CommercialAgreementCode__c' => new Map<String, Object>{ 'tagValue' => 'ACAI' }
            }
        };

        List<Object> attributes = new List<Object>{
            createAttr('SIAE-ATTR-RADIO', '2')
        };
        Map<String, Object> radioAttrTag = (Map<String, Object>) ((Map<String, Object>) attributes[0]).get('tagValue');
        radioAttrTag.put('SIAE_DeviceTotalPrice', new Map<String, Object>{ 'tagValue' => '20' });

        MockIndustriesContextAdapter mockCtx = new MockIndustriesContextAdapter();
        mockCtx.queryResponse = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItem' => new List<Object>{ item1 },
                'SalesTransactionItemAttribute' => attributes
            }
        };

        Test.startTest();
        SIAE_POSH_PricingMdAPlan.executeInternal('CTX-DDA-FULLDISCOUNT', mockCtx);
        Test.stopTest();

        String paymentItemsJson = extractPaymentItemsJson(mockCtx.lastUpdateInput);
        System.assertNotEquals(null, paymentItemsJson, 'SIAE_PaymentItems__c deve essere valorizzato');

        PricingPaymentItem.Wrapper wrapper = parsePaymentWrapper(paymentItemsJson);

        PricingPaymentItem ddaItem = findPaymentItemByCode(wrapper, 'DDA', 'T2216');
        System.assertNotEquals(null, ddaItem, 'PaymentItem DDA T2216 deve essere presente anche con sconto 100%');
        System.assertEquals(
            '0.00',
            ddaItem.amount,
            'Sconto 100% deve azzerare il PaymentItem DDA'
        );

        PricingPaymentItem siDdaItem = findPaymentItemByCode(wrapper, 'SI_DDA', 'SD3760');
        System.assertNotEquals(
            null,
            siDdaItem,
            'PaymentItem SI_DDA deve essere generato anche quando lo sconto DDA azzera i PaymentItem DDA'
        );
    }

    @IsTest
    static void testExecuteInternal_FlatRateDiscountedByCommercialAgreement() {
        Product2 prod = new Product2(
            Name = 'Prodotto Flat Sconto CA',
            Family = 'AA',
            ProductCode = 'SIAE-PROD-FLAT-CA-TEST',
            IsActive = true
        );
        insert prod;

        insert new SIAE_AccordoCommerciale__c(
            SIAE_CodiceAccordoCommerciale__c = 'ACAI',
            SIAE_CodiceDiIncrocio__c = 'AA',
            SIAE_RiduzioneCompensoBase__c = 0.20
        );

        Map<String, Object> item1 = new Map<String, Object>{
            'dataPath' => new List<Object>{ 'CTX-FLAT-CA', 'Order', 'item1' },
            'tagValue' => new Map<String, Object>{
                'LineItem' => new Map<String, Object>{ 'tagValue' => 'item1' },
                'Product' => new Map<String, Object>{ 'tagValue' => prod.Id },
                'ItemNetTotalPrice' => new Map<String, Object>{ 'tagValue' => 999.0 },
                'SIAE_CommercialAgreementCode__c' => new Map<String, Object>{ 'tagValue' => 'ACAI' },
                'SIAE_TypeOfFlatRate__c' => new Map<String, Object>{ 'tagValue' => 'FLAT_AUDIO' },
                'SIAE_FlatAudio__c' => new Map<String, Object>{ 'tagValue' => 100.0 },
                'SIAE_CoeffMaggiorazioneMQ__c' => new Map<String, Object>{ 'tagValue' => 1.5 }
            }
        };

        MockIndustriesContextAdapter mockCtx = new MockIndustriesContextAdapter();
        mockCtx.queryResponse = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItem' => new List<Object>{ item1 },
                'SalesTransactionItemAttribute' => new List<Object>()
            }
        };

        Test.startTest();
        SIAE_POSH_PricingMdAPlan.executeInternal('CTX-FLAT-CA', mockCtx);
        Test.stopTest();

        System.assertEquals(
            120.00,
            extractAttributeValue(mockCtx.lastUpdateInput, 'SIAE_TotalDA__c'),
            'La riduzione compenso base deve essere applicata alla flat con i coefficienti: 100 x 1.5 x (1 - 0.20)'
        );

        System.assertEquals(
            30.00,
            extractAttributeValue(mockCtx.lastUpdateInput, 'SIAE_TotalDiscountCADA__c'),
            'Lo sconto CA DA deve essere il delta sulla base flat, non sul prezzo a consumo'
        );

        System.assertEquals(
            0.20,
            extractAttributeValue(mockCtx.lastUpdateInput, 'SIAE_DDADiscountPercent__c'),
            'La percentuale di riduzione DDA deve essere tracciata anche sulle righe flat'
        );

        System.assertEquals(
            120.00,
            extractAttributeValue(mockCtx.lastUpdateInput, 'NetTotalPrice'),
            'Il totale riga flat deve coincidere con il TotalDA scontato quando non ci sono diritti connessi'
        );
    }

    @IsTest
    static void testExecuteInternal_FlatRateQuotaCalculatedOnDiscountedFlatNet() {
        Product2 prod = new Product2(
            Name = 'Prodotto Flat Quota CA',
            Family = 'CC',
            ProductCode = 'SIAE-PROD-FLAT-QUOTA-TEST',
            IsActive = true
        );
        insert prod;

        insert new SIAE_AccordoCommerciale__c(
            SIAE_CodiceAccordoCommerciale__c = 'ACAI',
            SIAE_CodiceDiIncrocio__c = 'CC',
            SIAE_RiduzioneCompensoBase__c = 0.50,
            SIAE_VoceQuota__c = 'QA-TEST',
            SIAE_PercentualeQuotaSuNettoDDA__c = 0.10
        );

        Map<String, Object> item1 = new Map<String, Object>{
            'dataPath' => new List<Object>{ 'CTX-FLAT-QUOTA', 'Order', 'item1' },
            'tagValue' => new Map<String, Object>{
                'LineItem' => new Map<String, Object>{ 'tagValue' => 'item1' },
                'Product' => new Map<String, Object>{ 'tagValue' => prod.Id },
                'ItemNetTotalPrice' => new Map<String, Object>{ 'tagValue' => 999.0 },
                'SIAE_CommercialAgreementCode__c' => new Map<String, Object>{ 'tagValue' => 'ACAI' },
                'SIAE_TypeOfFlatRate__c' => new Map<String, Object>{ 'tagValue' => 'FLAT_AUDIO_VIDEO' },
                'SIAE_FlatVideo__c' => new Map<String, Object>{ 'tagValue' => 200.0 }
            }
        };

        MockIndustriesContextAdapter mockCtx = new MockIndustriesContextAdapter();
        mockCtx.queryResponse = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItem' => new List<Object>{ item1 },
                'SalesTransactionItemAttribute' => new List<Object>()
            }
        };

        Test.startTest();
        SIAE_POSH_PricingMdAPlan.executeInternal('CTX-FLAT-QUOTA', mockCtx);
        Test.stopTest();

        System.assertEquals(
            10.00,
            extractAttributeValue(mockCtx.lastUpdateInput, 'SIAE_TotalCommercialAgreement__c'),
            'La quota su netto DDA deve essere calcolata sul flat netto scontato: 200 x (1 - 0.50) x 0.10'
        );

        System.assertEquals(
            110.00,
            extractAttributeValue(mockCtx.lastUpdateInput, 'SIAE_TotalDA__c'),
            'SIAE_TotalDA__c deve sommare la quota associativa alla flat scontata'
        );
    }

}