@IsTest
private class SIAE_PREH_PricingMdAPlan_T {

    private class MockIndustriesContextAdapter implements RCAContextGateway {
        public Map<String, Object> salesItemResponse;
        public Map<String, Object> attrResponse;
        public Map<String, Object> lastUpdateInput;
        public Boolean updateCalled = false;

        public Map<String, Object> queryTags(Map<String, Object> input) {
            Map<String, Object> queryResult = new Map<String, Object>();
            queryResult.putAll((Map<String, Object>) salesItemResponse.get('queryResult'));
            queryResult.putAll((Map<String, Object>) attrResponse.get('queryResult'));
            return new Map<String, Object>{ 'queryResult' => queryResult };
        }

        public void updateContextAttributes(Map<String, Object> input) {
            updateCalled = true;
            lastUpdateInput = input;
        }
    }

    @TestSetup
    static void setupData() {
        Product2 p = new Product2(
            Name = 'Prodotto Test',
            IsActive = true
        );
        insert p;

        SIAE_ConfigurazionePricing__c conf = new SIAE_ConfigurazionePricing__c();
        conf.SIAE_Product2__c = p.Id;
        conf.SIAE_Attivo__c = true;
        conf.SIAE_UsaDefaultTypeCoverage__c = true;
        conf.SIAE_UsaCoeffStagionalita__c = true;
        conf.SIAE_UsaMaggiorazioneEsterna__c = true;
        conf.SIAE_UsaMaggiorazioneMQ__c = true;
        conf.SIAE_UsaMaggiorazioneDipendenti__c = true;
        conf.SIAE_UsaMaggiorazioneTV40__c = true;
        conf.SIAE_DefaultTypeCoverageValue__c = 'Annuale';
        conf.SIAE_CoeffStag_Annuale__c = 1;
        conf.SIAE_CoeffStag_Semestrale__c = 0.6;
        conf.SIAE_CoeffStag_Trimestrale__c = 0.4;
        conf.SIAE_CoeffStag_Mensile__c = 0.2;
        conf.SIAE_AreeEsterne_ValoreNo__c = 1;
        conf.SIAE_AreeEsterne_ValoreFino50__c = 1.1;
        conf.SIAE_AreeEsterne_ValoreOltre50__c = 1.2;
        conf.SIAE_MQ_SogliaBase__c = 500;
        conf.SIAE_MQ_Tranche__c = 100;
        conf.SIAE_MQ_IncrementoPerTranche__c = 0.1;
        conf.SIAE_MQ_CoeffBase__c = 1;
        conf.SIAE_Dip_SogliaBase__c = 200;
        conf.SIAE_Dip_Tranche__c = 100;
        conf.SIAE_Dip_ImportoRadio__c = 10;
        conf.SIAE_Dip_ImportoAudio__c = 20;
        conf.SIAE_Dip_ImportoVideo__c = 30;
        conf.SIAE_TV40_Coefficiente__c = 2;
        conf.SIAE_DifferenziaAltoparlanti__c = true;
        conf.SIAE_UsaCompensoUnico__c = true;
        conf.SIAE_UsaDividiCompenso__c = true;
        conf.SIAE_DividiCompensoValore__c = 0.5;
        conf.SIAE_NuovaStruttura_Valore__c = 1.3;
        conf.SIAE_LicenzaRistorazione_Valore__c = 1.4;
        insert conf;
    }

    @IsTest
    static void testExecuteInternal_NoLineItems() {
        MockIndustriesContextAdapter mockCtx = new MockIndustriesContextAdapter();
        mockCtx.salesItemResponse = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItem' => new List<Object>()
            }
        };
        mockCtx.attrResponse = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItemAttribute' => new List<Object>()
            }
        };

        SIAE_PREH_PricingMdAPlan.ProcessResult res =
            SIAE_PREH_PricingMdAPlan.executeInternal('CTX-001', mockCtx);

        System.assertEquals(true, res.success);
        System.assertEquals('SIAE_PreHook_V1: nessun line item trovato.', res.message);
        System.assertEquals(false, mockCtx.updateCalled);
    }

    @IsTest
    static void testExecuteInternal_UpdateGenerated() {
        Id productId = [SELECT Id FROM Product2 LIMIT 1].Id;

        Map<String, Object> item1 = new Map<String, Object>{
            'dataPath' => new List<Object>{ 'CTX-001', 'ORDER-001', 'LINECTX-001' },
            'tagValue' => new Map<String, Object>{
                'Product' => new Map<String, Object>{ 'tagValue' => (String)productId },
                'LineItem' => new Map<String, Object>{ 'tagValue' => 'QLI-001', 'dmlStatus' => 'UPSERT' },
                'LineItemPath' => new Map<String, Object>{ 'tagValue' => 'QLI-001/child', 'dmlStatus' => 'UPSERT' },
                'SIAE_TypeOfCoverage__c' => new Map<String, Object>{ 'tagValue' => null }
            }
        };

        Map<String, Object> attr1 = new Map<String, Object>{
            'dataPath' => new List<Object>{ 'CTX-001', 'ORDER-001', 'LINECTX-001', 'ATTR-001' },
            'tagValue' => new Map<String, Object>{
                'AttributeDefinitionCode' => new Map<String, Object>{ 'tagValue' => 'SIAE-ATTR-QTA' },
                'AttributeValue' => new Map<String, Object>{ 'tagValue' => '650' },
                'SalesTransactionItemAttrParent' => new Map<String, Object>{ 'tagValue' => 'QLI-001' }
            }
        };
        Map<String, Object> attr2 = new Map<String, Object>{
            'dataPath' => new List<Object>{ 'CTX-001', 'ORDER-001', 'LINECTX-001', 'ATTR-002' },
            'tagValue' => new Map<String, Object>{
                'AttributeDefinitionCode' => new Map<String, Object>{ 'tagValue' => 'SIAE-ATTR-AREE-EST' },
                'AttributeValue' => new Map<String, Object>{ 'tagValue' => 'SI' },
                'SalesTransactionItemAttrParent' => new Map<String, Object>{ 'tagValue' => 'QLI-001' }
            }
        };
        Map<String, Object> attr3 = new Map<String, Object>{
            'dataPath' => new List<Object>{ 'CTX-001', 'ORDER-001', 'LINECTX-001', 'ATTR-003' },
            'tagValue' => new Map<String, Object>{
                'AttributeDefinitionCode' => new Map<String, Object>{ 'tagValue' => 'SIAE-ATTR-LUOGO' },
                'AttributeValue' => new Map<String, Object>{ 'tagValue' => 'Solo a terra' },
                'SalesTransactionItemAttrParent' => new Map<String, Object>{ 'tagValue' => 'QLI-001' }
            }
        };
        Map<String, Object> attr4 = new Map<String, Object>{
            'dataPath' => new List<Object>{ 'CTX-001', 'ORDER-001', 'LINECTX-001', 'ATTR-004' },
            'tagValue' => new Map<String, Object>{
                'AttributeDefinitionCode' => new Map<String, Object>{ 'tagValue' => 'SIAE-ATTR-LIC-RIST' },
                'AttributeValue' => new Map<String, Object>{ 'tagValue' => 'SI' },
                'SalesTransactionItemAttrParent' => new Map<String, Object>{ 'tagValue' => 'QLI-001' }
            }
        };
        Map<String, Object> attr5 = new Map<String, Object>{
            'dataPath' => new List<Object>{ 'CTX-001', 'ORDER-001', 'LINECTX-001', 'ATTR-005' },
            'tagValue' => new Map<String, Object>{
                'AttributeDefinitionCode' => new Map<String, Object>{ 'tagValue' => 'SIAE-ATTR-NUOVA-STRU' },
                'AttributeValue' => new Map<String, Object>{ 'tagValue' => 'SI' },
                'SalesTransactionItemAttrParent' => new Map<String, Object>{ 'tagValue' => 'QLI-001' }
            }
        };

        MockIndustriesContextAdapter mockCtx = new MockIndustriesContextAdapter();
        mockCtx.salesItemResponse = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItem' => new List<Object>{ item1 }
            }
        };
        mockCtx.attrResponse = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItemAttribute' => new List<Object>{ attr1, attr2, attr3, attr4, attr5 }
            }
        };

        Test.startTest();
        SIAE_PREH_PricingMdAPlan.ProcessResult res =
            SIAE_PREH_PricingMdAPlan.executeInternal('CTX-001', mockCtx);
        Test.stopTest();

        List<Object> updates = (List<Object>) mockCtx.lastUpdateInput.get('nodePathAndAttributes');
        System.assertEquals(1, updates.size());

        Map<String, Object> firstUpdate = (Map<String, Object>) updates[0];
        Map<String, Object> nodePath = (Map<String, Object>) firstUpdate.get('nodePath');
        List<Object> dataPath = (List<Object>) nodePath.get('dataPath');

        System.assertEquals(2, dataPath.size());
        System.assertEquals('ORDER-001', (String)dataPath[0]);
        System.assertEquals('LINECTX-001', (String)dataPath[1]);

        List<Object> attrs = (List<Object>) firstUpdate.get('attributes');
        System.assertEquals(15, attrs.size());

        Map<String, Object> attrCoeffMq = (Map<String, Object>) attrs[0];
        Map<String, Object> attrCoeffAree = (Map<String, Object>) attrs[1];
        Map<String, Object> attrCoeffStag = (Map<String, Object>) attrs[2];
        Map<String, Object> attrTypeCoverage = (Map<String, Object>) attrs[3];
        Map<String, Object> attrCoeffTv40 = (Map<String, Object>) attrs[4];
        Map<String, Object> attrSellingModel = (Map<String, Object>) attrs[14];

        System.assertEquals('SIAE_CoeffMaggiorazioneMQ__c', (String) attrCoeffMq.get('attributeName'));
        System.assertEquals('SIAE_CoeffAreeEsterne__c', (String) attrCoeffAree.get('attributeName'));
        System.assertEquals('SIAE_CoeffStagionalita__c', (String) attrCoeffStag.get('attributeName'));
        System.assertEquals('SIAE_TypeOfCoverage__c', (String) attrTypeCoverage.get('attributeName'));
        System.assertEquals('SIAE_CoeffMaggiorazioneTV40__c', (String) attrCoeffTv40.get('attributeName'));
        System.assertEquals('ProductSellingModel', (String) attrSellingModel.get('attributeName'));
    }

    @IsTest
    static void testExecuteInternal_PicklistAttribute_ResolvesAndRewritesContext() {
        Id productId = [SELECT Id FROM Product2 LIMIT 1].Id;

        AttributePicklist picklist = new AttributePicklist(Name = 'Test Classificazione Plan');
        insert picklist;

        AttributePicklistValue pv = new AttributePicklistValue(
            Name = 'Non convenzionata',
            PicklistId = picklist.Id,
            Code = 'NON-CONV-PLAN-TEST',
            Value = 'Non convenzionata'
        );
        insert pv;

        Map<String, Object> item1 = new Map<String, Object>{
            'dataPath' => new List<Object>{ 'CTX-001', 'ORDER-001', 'LINECTX-001' },
            'tagValue' => new Map<String, Object>{
                'Product' => new Map<String, Object>{ 'tagValue' => (String)productId },
                'LineItem' => new Map<String, Object>{ 'tagValue' => 'QLI-001', 'dmlStatus' => 'UPSERT' },
                'LineItemPath' => new Map<String, Object>{ 'tagValue' => 'QLI-001/child', 'dmlStatus' => 'UPSERT' }
            }
        };

        Map<String, Object> attrClass = new Map<String, Object>{
            'dataPath' => new List<Object>{ 'CTX-001', 'ORDER-001', 'LINECTX-001', 'LINECTX-001-ATTR-CLASS' },
            'tagValue' => new Map<String, Object>{
                'AttributeDefinitionCode' => new Map<String, Object>{ 'tagValue' => 'SIAE-ATTR-CLASS' },
                'AttributePicklistValue' => new Map<String, Object>{ 'tagValue' => pv.Id },
                'SalesTransactionItemAttrParent' => new Map<String, Object>{ 'tagValue' => 'QLI-001' }
            }
        };

        MockIndustriesContextAdapter mockCtx = new MockIndustriesContextAdapter();
        mockCtx.salesItemResponse = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItem' => new List<Object>{ item1 }
            }
        };
        mockCtx.attrResponse = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItemAttribute' => new List<Object>{ attrClass }
            }
        };

        Test.startTest();
        SIAE_PREH_PricingMdAPlan.ProcessResult res =
            SIAE_PREH_PricingMdAPlan.executeInternal('CTX-001', mockCtx);
        Test.stopTest();

        List<Object> updates = (List<Object>) mockCtx.lastUpdateInput.get('nodePathAndAttributes');
        System.assertEquals(2, updates.size(), 'Update sul nodo attributo (picklist risolto) + update sull item (coefficienti)');

        Map<String, Object> attributeUpdate = (Map<String, Object>) updates[0];
        Map<String, Object> nodePath = (Map<String, Object>) attributeUpdate.get('nodePath');
        List<Object> dataPath = (List<Object>) nodePath.get('dataPath');

        System.assertEquals(3, dataPath.size(), 'Path a livello attributo (senza il contextId)');
        System.assertEquals('ORDER-001', (String) dataPath[0]);
        System.assertEquals('LINECTX-001', (String) dataPath[1]);
        System.assertEquals('LINECTX-001-ATTR-CLASS', (String) dataPath[2]);

        List<Object> attrs = (List<Object>) attributeUpdate.get('attributes');
        System.assertEquals(1, attrs.size());
        Map<String, Object> attrValueUpdate = (Map<String, Object>) attrs[0];
        System.assertEquals('AttributeValue', (String) attrValueUpdate.get('attributeName'));
        System.assertEquals(
            'Non convenzionata',
            (String) attrValueUpdate.get('attributeValue'),
            'Il valore Picklist deve essere risolto e riscritto sul context'
        );
    }

    @IsTest
    static void testExecuteInternal_UnresolvedAttrParentTag_FallsBackToDataPathLineKey() {
        Id productId = [SELECT Id FROM Product2 LIMIT 1].Id;

        // Scenario reale "placeSalesTransaction": riga e attributo creati nella stessa
        // chiamata Composite Graph con riferimento template (@{refX.id}) mai risolto
        // nel tag SalesTransactionItemAttrParent, mentre il dataPath resta coerente.
        Map<String, Object> item1 = new Map<String, Object>{
            'dataPath' => new List<Object>{ 'CTX-001', 'QUOTE-001', 'refSpazio1' },
            'tagValue' => new Map<String, Object>{
                'Product'  => new Map<String, Object>{ 'tagValue' => (String)productId },
                'LineItem' => new Map<String, Object>{ 'tagValue' => 'refSpazio1', 'dmlStatus' => 'UPSERT' }
            }
        };

        Map<String, Object> attrLicRist = new Map<String, Object>{
            'dataPath' => new List<Object>{ 'CTX-001', 'QUOTE-001', 'refSpazio1', 'refSpazio1-SIAE-ATTR-RIST' },
            'tagValue' => new Map<String, Object>{
                'AttributeDefinitionCode' => new Map<String, Object>{ 'tagValue' => 'SIAE-ATTR-LIC-RIST' },
                'AttributeValue' => new Map<String, Object>{ 'tagValue' => 'SI' },
                'SalesTransactionItemAttrParent' => new Map<String, Object>{ 'tagValue' => '@{refSpazio1.id}' }
            }
        };

        MockIndustriesContextAdapter mockCtx = new MockIndustriesContextAdapter();
        mockCtx.salesItemResponse = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItem' => new List<Object>{ item1 }
            }
        };
        mockCtx.attrResponse = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItemAttribute' => new List<Object>{ attrLicRist }
            }
        };

        Test.startTest();
        SIAE_PREH_PricingMdAPlan.ProcessResult res =
            SIAE_PREH_PricingMdAPlan.executeInternal('CTX-001', mockCtx);
        Test.stopTest();

        List<Object> updates = (List<Object>) mockCtx.lastUpdateInput.get('nodePathAndAttributes');
        Map<String, Object> itemUpdate = (Map<String, Object>) updates[updates.size() - 1];
        List<Object> attrs = (List<Object>) itemUpdate.get('attributes');

        String licenzaRistValue = null;
        for (Object a : attrs) {
            Map<String, Object> m = (Map<String, Object>) a;
            if ('SIAE_LicenzaRistorazione__c'.equals((String) m.get('attributeName'))) {
                licenzaRistValue = String.valueOf(m.get('attributeValue'));
            }
        }

        System.assertEquals(
            '1',
            licenzaRistValue,
            'licRis=SI deve dare coefficiente 1 anche quando SalesTransactionItemAttrParent e un riferimento @{...} non risolto'
        );
    }

    @IsTest
    static void testExecuteInternal_SkipDeletedItem() {
        Id productId = [SELECT Id FROM Product2 LIMIT 1].Id;

        Map<String, Object> deletedItem = new Map<String, Object>{
            'dataPath' => new List<Object>{ 'CTX-001', 'ORDER-001', 'LINECTX-001' },
            'tagValue' => new Map<String, Object>{
                'Product' => new Map<String, Object>{ 'tagValue' => (String)productId },
                'LineItem' => new Map<String, Object>{ 'tagValue' => 'QLI-001', 'dmlStatus' => 'DELETED' },
                'LineItemPath' => new Map<String, Object>{ 'tagValue' => 'QLI-001/child', 'dmlStatus' => 'DELETED' }
            }
        };

        MockIndustriesContextAdapter mockCtx = new MockIndustriesContextAdapter();
        mockCtx.salesItemResponse = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItem' => new List<Object>{ deletedItem }
            }
        };
        mockCtx.attrResponse = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItemAttribute' => new List<Object>()
            }
        };

        SIAE_PREH_PricingMdAPlan.ProcessResult res =
            SIAE_PREH_PricingMdAPlan.executeInternal('CTX-001', mockCtx);

        System.assertEquals(true, res.success);
        System.assertEquals('SIAE_PreHook_V1: completato con 0 update.', res.message);
        System.assertEquals(false, mockCtx.updateCalled);
    }

    @IsTest
    static void testExecuteInternal_MissingConfiguration_Fails() {
        Map<String, Object> itemWithoutConf = new Map<String, Object>{
            'dataPath' => new List<Object>{ 'CTX-001', 'ORDER-001', 'LINECTX-001' },
            'tagValue' => new Map<String, Object>{
                'LineItem' => new Map<String, Object>{ 'tagValue' => 'QLI-001', 'dmlStatus' => 'UPSERT' }
            }
        };

        MockIndustriesContextAdapter mockCtx = new MockIndustriesContextAdapter();
        mockCtx.salesItemResponse = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItem' => new List<Object>{ itemWithoutConf }
            }
        };
        mockCtx.attrResponse = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItemAttribute' => new List<Object>()
            }
        };

        SIAE_PREH_PricingMdAPlan.ProcessResult res =
            SIAE_PREH_PricingMdAPlan.executeInternal('CTX-001', mockCtx);

        System.assertEquals(false, res.success, 'Senza configurazione il Plan resta in errore, come prima della migrazione');
        System.assertEquals(false, mockCtx.updateCalled);
    }
}