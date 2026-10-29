@IsTest
private class SIAE_PREH_PricingMdAFlow_T {

    // Utility: crea Product2 e relativa Configurazione Pricing attiva
    private static Product2 createProductWithConfig() {
        return createProductWithConfig(false);
    }

    private static Product2 createProductWithConfig(Boolean differenziaAltoparlanti) {
        Product2 p = new Product2(Name = 'Prod Test', Family = 'Test', IsActive = true);
        insert p;

        // Valori minimi per evitare null pointer nei calcoli
        SIAE_ConfigurazionePricing__c cfg = new SIAE_ConfigurazionePricing__c(
            SIAE_Attivo__c = true,
            SIAE_Product2__c = p.Id,
            SIAE_UsaDefaultTypeCoverage__c = true,
            SIAE_UsaCoeffStagionalita__c = true,
            SIAE_UsaMaggiorazioneEsterna__c = true,
            SIAE_UsaMaggiorazioneMQ__c = true,
            SIAE_UsaMaggiorazioneDipendenti__c = true,
            SIAE_UsaMaggiorazioneTV40__c = true,
            SIAE_DefaultTypeCoverageValue__c = 'ANNUALE',
            SIAE_CoeffStag_Annuale__c = 1,
            SIAE_CoeffStag_Semestrale__c = 0.6,
            SIAE_CoeffStag_Trimestrale__c = 0.35,
            SIAE_CoeffStag_Mensile__c = 0.1,
            SIAE_AreeEsterne_ValoreNo__c = 1,
            SIAE_AreeEsterne_ValoreFino50__c = 1.1,
            SIAE_AreeEsterne_ValoreOltre50__c = 1.2,
            SIAE_MQ_SogliaBase__c = 500,
            SIAE_MQ_Tranche__c = 100,
            SIAE_MQ_IncrementoPerTranche__c = 0.05,
            SIAE_MQ_CoeffBase__c = 1,
            SIAE_Dip_SogliaBase__c = 200,
            SIAE_Dip_Tranche__c = 50,
            SIAE_Dip_ImportoRadio__c = 10,
            SIAE_Dip_ImportoAudio__c = 20,
            SIAE_Dip_ImportoVideo__c = 30,
            SIAE_TV40_Coefficiente__c = 1.15,
            SIAE_NuovaStruttura_Valore__c = 0.9,
            SIAE_LicenzaRistorazione_Valore__c = 1.1,
            SIAE_DifferenziaAltoparlanti__c = differenziaAltoparlanti
        );
        insert cfg;

        return p;
    }

    private static List<SIAE_PREH_PricingMdAFlow.FlowOutput> runFlowWithJson(String jsonStr) {
        SIAE_PREH_PricingMdAFlow.FlowInput inp = new SIAE_PREH_PricingMdAFlow.FlowInput();
        inp.jsonDataString = jsonStr;
        List<SIAE_PREH_PricingMdAFlow.FlowInput> inputs = new List<SIAE_PREH_PricingMdAFlow.FlowInput>{ inp };
        return SIAE_PREH_PricingMdAFlow.execute(inputs);
    }

    // Test 1: input vuoto - deve restituire ERROR
    @IsTest
    static void testBlankInput_returnsError() {
        Test.startTest();
        List<SIAE_PREH_PricingMdAFlow.FlowOutput> out = runFlowWithJson(null);
        Test.stopTest();

        System.assertEquals(1, out.size(), 'Deve tornare un solo output');
        System.assertEquals('ERROR', out[0].status, 'Status atteso ERROR');
        System.assertEquals(null, out[0].enrichedJsonString, 'Restituisce lo stesso (null) input');
        System.assert(out[0].message != null && out[0].message.contains('nullo o vuoto'), 'Messaggio deve spiegare input vuoto');
    }

    // Test 2: JSON senza SalesTransaction - SUCCESS e JSON invariato
    @IsTest
    static void testNoSalesTransaction_returnsSuccessNoChange() {
        String input = '{ "SomeOtherKey": [] }';

        Test.startTest();
        List<SIAE_PREH_PricingMdAFlow.FlowOutput> out = runFlowWithJson(input);
        Test.stopTest();

        System.assertEquals(1, out.size());
        System.assertEquals('SUCCESS', out[0].status);
        System.assert(out[0].message != null && out[0].message.contains('nessuna SalesTransaction'), 'Messaggio atteso');
        System.assertEquals(input, out[0].enrichedJsonString, 'JSON invariato');
    }

    // Test 3: Item valido con configurazione - verifica che i campi vengano popolati
    @IsTest
    static void testSingleItem_withConfig_addsCalculatedFields() {
        Product2 p = createProductWithConfig();

        // JSON con un item attivo
        String input = '{'+
            '  "SalesTransaction": ['+
            '    {'+
            '      "SalesTransactionItem": ['+
            '        {'+
            '          "Product": "'+ String.valueOf(p.Id) +'",'+
            '          "dmlStatus": "INSERT",'+
            '          "SIAE_TypeOfCoverage__c": "MENSILE",'+
            '          "SalesTransactionItemAttribute": ['+
            '            {"AttributeDefinitionCode": "SIAE-ATTR-QTA", "AttributeValue": "650"},'+
            '            {"AttributeDefinitionCode": "SIAE-ATTR-AREE-EST", "AttributeValue": "OLTRE_50"},'+
            '            {"AttributeDefinitionCode": "SIAE-ATTR-LIC-RIST", "AttributeValue": "SI"},'+
            '            {"AttributeDefinitionCode": "SIAE-ATTR-NUOVA-STRU", "AttributeValue": "SI"}'+
            '          ]'+
            '        }'+
            '      ]'+
            '    }'+
            '  ]'+
            '}';

        Test.startTest();
        List<SIAE_PREH_PricingMdAFlow.FlowOutput> out = runFlowWithJson(input);
        Test.stopTest();

        System.assertEquals(1, out.size());
        System.assertEquals('SUCCESS', out[0].status, 'Elaborazione deve avere successo');

        // Deserializza JSON arricchito per controllare i campi
        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(out[0].enrichedJsonString);
        List<Object> stList = getAsList(root.get('SalesTransaction'));
        System.assertEquals(1, stList.size(), 'Una sola ST');

        Map<String, Object> st = (Map<String, Object>) stList[0];
        List<Object> items = getAsList(st.get('SalesTransactionItem'));
        System.assertEquals(1, items.size(), 'Un item');

        Map<String, Object> item = (Map<String, Object>) items[0];

        // Campi che la classe dovrebbe aggiungere
        System.assert(item.containsKey('SIAE_CoeffMaggiorazioneMQ__c'), 'Coeff MQ presente');
        System.assert(item.containsKey('SIAE_CoeffAreeEsterne__c'), 'Coeff aree esterne presente');
        System.assert(item.containsKey('SIAE_CoeffStagionalita__c'), 'Coeff stagionalità presente');
        System.assert(item.containsKey('SIAE_TypeOfCoverage__c'), 'TOC normalizzato presente');
        System.assert(item.containsKey('SIAE_CoeffMaggiorazioneTV40__c'), 'Coeff TV40 presente');
        System.assert(item.containsKey('SIAE_CoeffMaggiorazioneDipendentiRadio__c'), 'Importo dip Radio presente');
        System.assert(item.containsKey('SIAE_CoeffMaggiorazioneDipendentiAudio__c'), 'Importo dip Audio presente');
        System.assert(item.containsKey('SIAE_CoeffMaggiorazioneDipendentiVideo__c'), 'Importo dip Video presente');
        System.assert(item.containsKey('SIAE_LicenzaRistorazione__c'), 'Licenza Ristorazione presente');
        System.assert(item.containsKey('SIAE_NuovaStruttura__c'), 'Nuova Struttura presente');

        // Verifiche base sui valori (non calcoliamo qui la formula delle utility)
        Object toc = item.get('SIAE_TypeOfCoverage__c');
        System.assertNotEquals(null, toc, 'TOC non nullo');
    }

    // Test 4: Item DELETED deve essere ignorato (nessun arricchimento)
    @IsTest
    static void testDeletedItem_isIgnored() {
        Product2 p = createProductWithConfig();

        String input = '{'+
            '  "SalesTransaction": ['+
            '    {'+
            '      "SalesTransactionItem": ['+
            '        {'+
            '          "Product": "'+ String.valueOf(p.Id) +'",'+
            '          "dmlStatus": "DELETED",'+
            '          "SalesTransactionItemAttribute": ['+
            '            {"AttributeDefinitionCode": "SIAE-ATTR-QTA", "AttributeValue": "100"}'+
            '          ]'+
            '        }'+
            '      ]'+
            '    }'+
            '  ]'+
            '}';

        Test.startTest();
        List<SIAE_PREH_PricingMdAFlow.FlowOutput> out = runFlowWithJson(input);
        Test.stopTest();

        System.assertEquals(1, out.size());
        System.assertEquals('SUCCESS', out[0].status);

        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(out[0].enrichedJsonString);
        List<Object> stList = getAsList(root.get('SalesTransaction'));
        Map<String, Object> st = (Map<String, Object>) stList[0];
        List<Object> items = getAsList(st.get('SalesTransactionItem'));
        Map<String, Object> item = (Map<String, Object>) items[0];

        // I campi calcolati non dovrebbero essere presenti perché l'item è ignorato
        System.assert(!item.containsKey('SIAE_CoeffMaggiorazioneMQ__c'), 'Item deleted non deve essere arricchito');
        System.assertEquals('DELETED', (String)item.get('dmlStatus'));
    }

    // Test 5: Nessuna configurazione per il prodotto - la classe deve gestire in sicurezza
    @IsTest
    static void testMissingConfig_handlesSafely() {
        // Creo un prodotto senza config
        Product2 p = new Product2(Name = 'NoCfg', Family = 'Test', IsActive = true);
        insert p;

        String input = '{'+
            '  "SalesTransaction": ['+
            '    {'+
            '      "SalesTransactionItem": ['+
            '        {'+
            '          "Product": "'+ String.valueOf(p.Id) +'",'+
            '          "dmlStatus": "INSERT",'+
            '          "SalesTransactionItemAttribute": ['+
            '            {"AttributeDefinitionCode": "SIAE-ATTR-QTA", "AttributeValue": "50"}'+
            '          ]'+
            '        }'+
            '      ]'+
            '    }'+
            '  ]'+
            '}';

        Test.startTest();
        List<SIAE_PREH_PricingMdAFlow.FlowOutput> out = runFlowWithJson(input);
        Test.stopTest();

        System.assertEquals(1, out.size());
        System.assertEquals('SUCCESS', out[0].status, 'Deve comunque completare senza eccezioni');

        // Anche senza config, la classe potrebbe aggiungere alcune chiavi con valori di default/0
        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(out[0].enrichedJsonString);
        List<Object> stList = getAsList(root.get('SalesTransaction'));
        Map<String, Object> st = (Map<String, Object>) stList[0];
        List<Object> items = getAsList(st.get('SalesTransactionItem'));
        Map<String, Object> item = (Map<String, Object>) items[0];

        // Non facciamo assunzioni forti sui valori, ma verifichiamo che non ci siano eccezioni e che l'output sia un JSON valido
        System.assertNotEquals(null, item, 'Item presente e deserializzato');
    }

    // Test 6: Config con SIAE_DifferenziaAltoparlanti__c attivo - valorizza i due tag
    @IsTest
    static void testDifferenziaAltoparlanti_activeConfig_setsBothTags() {
        Product2 p = createProductWithConfig(true);

        String input = '{'+
            '  "SalesTransaction": ['+
            '    {'+
            '      "SalesTransactionItem": ['+
            '        {'+
            '          "Product": "'+ String.valueOf(p.Id) +'",'+
            '          "dmlStatus": "INSERT",'+
            '          "SalesTransactionItemAttribute": []'+
            '        }'+
            '      ]'+
            '    }'+
            '  ]'+
            '}';

        Test.startTest();
        List<SIAE_PREH_PricingMdAFlow.FlowOutput> out = runFlowWithJson(input);
        Test.stopTest();

        System.assertEquals('SUCCESS', out[0].status);

        Map<String, Object> item = extractSingleItem(out[0].enrichedJsonString);

        System.assertEquals('Altoparlante', (String) item.get('SIAE_DiffAltoparlanti__c'), 'Tag Altoparlante atteso quando la config lo richiede');
        System.assertEquals('Monitor', (String) item.get('SIAE_DiffMonitor__c'), 'Tag Monitor atteso quando la config lo richiede');
    }

    // Test 7: Config senza SIAE_DifferenziaAltoparlanti__c - i due tag restano nulli
    @IsTest
    static void testDifferenziaAltoparlanti_inactiveConfig_leavesTagsNull() {
        Product2 p = createProductWithConfig(false);

        String input = '{'+
            '  "SalesTransaction": ['+
            '    {'+
            '      "SalesTransactionItem": ['+
            '        {'+
            '          "Product": "'+ String.valueOf(p.Id) +'",'+
            '          "dmlStatus": "INSERT",'+
            '          "SalesTransactionItemAttribute": []'+
            '        }'+
            '      ]'+
            '    }'+
            '  ]'+
            '}';

        Test.startTest();
        List<SIAE_PREH_PricingMdAFlow.FlowOutput> out = runFlowWithJson(input);
        Test.stopTest();

        System.assertEquals('SUCCESS', out[0].status);

        Map<String, Object> item = extractSingleItem(out[0].enrichedJsonString);

        System.assert(item.containsKey('SIAE_DiffAltoparlanti__c'), 'Chiave presente anche se nulla');
        System.assertEquals(null, item.get('SIAE_DiffAltoparlanti__c'), 'Nessuna differenziazione quando la config non la richiede');
        System.assertEquals(null, item.get('SIAE_DiffMonitor__c'), 'Nessuna differenziazione quando la config non la richiede');
    }

    // Test: ente pubblico (COND-SPE=SI) -> maggiorazione >200 dipendenti azzerata
    @IsTest
    static void testEntePubblico_condSpeSi_zeroesDipMaggiorazione() {
        Product2 p = createProductWithConfig(); // UsaMaggiorazioneDipendenti=true, soglia 200, tranche 50, importoRadio 10

        String input = '{'+
            '  "SalesTransaction": [ { "SalesTransactionItem": [ {'+
            '    "Product": "'+ String.valueOf(p.Id) +'", "dmlStatus": "INSERT",'+
            '    "SalesTransactionItemAttribute": ['+
            '      {"AttributeDefinitionCode": "SIAE-ATTR-QTA", "AttributeValue": "500"},'+
            '      {"AttributeDefinitionCode": "SIAE-ATTR-COND-SPE", "AttributeValue": "SI"}'+
            '    ] } ] } ]'+
            '}';

        Test.startTest();
        List<SIAE_PREH_PricingMdAFlow.FlowOutput> out = runFlowWithJson(input);
        Test.stopTest();

        System.assertEquals('SUCCESS', out[0].status);
        Map<String, Object> item = extractSingleItem(out[0].enrichedJsonString);

        // QTA reale invariata (nessuna falsificazione)
        System.assertEquals('500', qtaAttrValueOf(item), 'QTA reale non modificata');
        // Maggiorazione azzerata perche ente pubblico
        System.assertEquals(0, (Decimal) item.get('SIAE_CoeffMaggiorazioneDipendentiRadio__c'), 'Radio azzerato per ente pubblico');
        System.assertEquals(0, (Decimal) item.get('SIAE_CoeffMaggiorazioneDipendentiAudio__c'), 'Audio azzerato');
        System.assertEquals(0, (Decimal) item.get('SIAE_CoeffMaggiorazioneDipendentiVideo__c'), 'Video azzerato');
    }

    // Test: COND-SPE=NO -> maggiorazione calcolata sul numero reale
    @IsTest
    static void testEntePubblico_condSpeNo_keepsDipMaggiorazione() {
        Product2 p = createProductWithConfig();

        String input = '{'+
            '  "SalesTransaction": [ { "SalesTransactionItem": [ {'+
            '    "Product": "'+ String.valueOf(p.Id) +'", "dmlStatus": "INSERT",'+
            '    "SalesTransactionItemAttribute": ['+
            '      {"AttributeDefinitionCode": "SIAE-ATTR-QTA", "AttributeValue": "500"},'+
            '      {"AttributeDefinitionCode": "SIAE-ATTR-COND-SPE", "AttributeValue": "NO"}'+
            '    ] } ] } ]'+
            '}';

        Test.startTest();
        List<SIAE_PREH_PricingMdAFlow.FlowOutput> out = runFlowWithJson(input);
        Test.stopTest();

        Map<String, Object> item = extractSingleItem(out[0].enrichedJsonString);
        // scatti = ceil((500-200)/50) = 6 -> radio = 6 * 10 = 60
        System.assertEquals(60, (Decimal) item.get('SIAE_CoeffMaggiorazioneDipendentiRadio__c'), 'Maggiorazione sul reale con NO');
    }

    // Test: attributo Picklist con solo AttributePicklistValue (Id) -> deve essere
    // risolto nel testo e riscritto sul JSON arricchito prima della Pricing Procedure.
    @IsTest
    static void testPicklistAttribute_resolvesTextValueOnEnrichedJson() {
        Product2 p = createProductWithConfig();

        AttributePicklist picklist = new AttributePicklist(Name = 'Test Classificazione Flow');
        insert picklist;

        AttributePicklistValue pv = new AttributePicklistValue(
            Name = 'Capelli ed estetica',
            PicklistId = picklist.Id,
            Code = 'CAP-EST-FLOW-TEST',
            Value = 'Capelli ed estetica'
        );
        insert pv;

        String input = '{'+
            '  "SalesTransaction": [ { "SalesTransactionItem": [ {'+
            '    "Product": "'+ String.valueOf(p.Id) +'", "dmlStatus": "INSERT",'+
            '    "SalesTransactionItemAttribute": ['+
            '      {"AttributeDefinitionCode": "SIAE-ATTR-CLASS", "AttributePicklistValue": "'+ pv.Id +'"},'+
            '      {"AttributeDefinitionCode": "SIAE-ATTR-QTA", "AttributeValue": "35"}'+
            '    ] } ] } ]'+
            '}';

        Test.startTest();
        List<SIAE_PREH_PricingMdAFlow.FlowOutput> out = runFlowWithJson(input);
        Test.stopTest();

        System.assertEquals('SUCCESS', out[0].status);
        Map<String, Object> item = extractSingleItem(out[0].enrichedJsonString);

        String resolvedClass = null;
        for (Object attrObj : getAsList(item.get('SalesTransactionItemAttribute'))) {
            Map<String, Object> attr = (Map<String, Object>) attrObj;
            if ('SIAE-ATTR-CLASS'.equals((String) attr.get('AttributeDefinitionCode'))) {
                resolvedClass = (String) attr.get('AttributeValue');
            }
        }

        System.assertEquals(
            'Capelli ed estetica',
            resolvedClass,
            'Il valore Picklist deve essere risolto e riscritto su AttributeValue nel JSON arricchito'
        );
    }

    private static String qtaAttrValueOf(Map<String, Object> item) {
        for (Object attrObj : getAsList(item.get('SalesTransactionItemAttribute'))) {
            Map<String, Object> attr = (Map<String, Object>) attrObj;
            if ('SIAE-ATTR-QTA'.equals((String) attr.get('AttributeDefinitionCode'))) {
                return (String) attr.get('AttributeValue');
            }
        }
        return null;
    }

    private static Map<String, Object> extractSingleItem(String enrichedJsonString) {
        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(enrichedJsonString);
        Map<String, Object> st = (Map<String, Object>) getAsList(root.get('SalesTransaction'))[0];
        return (Map<String, Object>) getAsList(st.get('SalesTransactionItem'))[0];
    }

    // Helper locale identico alla logica della classe per la lettura lista
    private static List<Object> getAsList(Object node) {
        List<Object> result = new List<Object>();
        if (node != null) {
            if (node instanceof List<Object>) {
                result = (List<Object>) node;
            } else if (node instanceof Map<String, Object>) {
                result.add(node);
            }
        }
        return result;
    }
}