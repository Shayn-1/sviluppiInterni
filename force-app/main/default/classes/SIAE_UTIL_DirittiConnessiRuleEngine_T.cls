/**
 * @description       : Classe di test per SIAE_UTIL_DirittiConnessiRuleEngine
 * @author            : Gaetano Iuliano - gaetano.iuliano@nttdata.com
 * @group             : NTT Data
 * @last modified on  : 05-27-2026
 * @last modified by  : Gaetano Iuliano - gaetano.iuliano@nttdata.com
**/
@IsTest
private class SIAE_UTIL_DirittiConnessiRuleEngine_T {

    // Helper: crea un SalesTransactionItemNode minimale
    private static RCASalesTransaction.ItemNode buildNode(String lineItemId) {
        RCASalesTransaction.ItemNode node = new RCASalesTransaction.ItemNode();
        node.lineItemId = lineItemId;
        node.periodicityCoefficient = 1;
        node.discountDc = 0;
        return node;
    }

    @IsTest
    static void testEvaluate_NullItemNode() {
        SIAE_DTO_DirittiConnessiResult.LicenzaDetail res =
            SIAE_UTIL_DirittiConnessiRuleEngine.evaluate(null, null, null, null, null);
        System.assertNotEquals(null, res, 'Result non deve essere null');
        System.assertEquals(null, res.orderItemId, 'orderItemId deve essere null quando itemNode è null');
        System.assertEquals(0, res.dettagliDispositivi.size(), 'Nessun dettaglio quando regole null');
    }

    @IsTest
    static void testEvaluate_NoRules() {
        RCASalesTransaction.ItemNode node = buildNode('line-1');
        SIAE_DTO_DirittiConnessiResult.LicenzaDetail res =
            SIAE_UTIL_DirittiConnessiRuleEngine.evaluate(node, new Map<String,String>(), new List<SIAE_DirittiConnessiRule__c>(), new List<SIAE_DirittiConnessiTariffa__c>(), null);
        System.assertNotEquals(null, res, 'Result non deve essere null');
        System.assertEquals('line-1', res.orderItemId, 'orderItemId deve essere valorizzato');
        System.assertEquals(0, res.dettagliDispositivi.size(), 'Nessun dettaglio quando regole vuote');
    }

    @IsTest
    static void testCalculateUnitsToApplyStandard_and_withDeviceGroup() {
        // costruiamo regola con ApplyFrom/ApplyTo
        SIAE_DirittiConnessiRule__c rule = new SIAE_DirittiConnessiRule__c();
        rule.SIAE_ApplyFromUnit__c = 2;
        rule.SIAE_ApplyToUnit__c = 4;
        // invoke private method via reflection not possible, but methods are private.
        // Instead test via evaluate using minimal tariffa and rule that will match.
        rule.SIAE_Attribute__c = 'QTY';
        rule.SIAE_Operator__c = 'EQ';
        rule.SIAE_ValueFrom__c = '3';
        rule.SIAE_AttributeQuantity__c = 'QTY';
        rule.SIAE_Action__c = 'TARIFFA_BASE';
        rule.SIAE_DeviceType__c = 'DEV';
        rule.SIAE_RevenueItemDC__c = 'R1';

        // tariffa per device
        SIAE_DirittiConnessiTariffa__c t = new SIAE_DirittiConnessiTariffa__c();
        t.SIAE_ConfigName__c = 'CFG';
        t.SIAE_DeviceType__c = 'DEV';
        t.SIAE_Amount__c = 10;
        t.SIAE_BracketFrom__c = 0;
        t.SIAE_BracketTo__c = 999999;

        // attributi: QTY = 3 -> units applicable = from 2..3 => 2 units (2 and 3) => unitaDaApplicare = 2
        Map<String, String> attrs = new Map<String, String>{ 'QTY' => '3' };

        RCASalesTransaction.ItemNode node = buildNode('line-2');

        // config stub
        SIAE_DirittiConnessiConfig__mdt cfg = new SIAE_DirittiConnessiConfig__mdt();
        cfg.DeveloperName = 'CFG';

        List<SIAE_DirittiConnessiRule__c> rules = new List<SIAE_DirittiConnessiRule__c>{ rule };
        List<SIAE_DirittiConnessiTariffa__c> tariffs = new List<SIAE_DirittiConnessiTariffa__c>{ t };

        // Diagnostic assertions to verify intermediate steps
        System.assertEquals(true, SIAE_UTIL_DirittiConnessiRuleEngine.conditionMatches(rule, attrs), 'conditionMatches should be true for QTY=3 and ValueFrom=3');
        Decimal rateFound = SIAE_UTIL_DirittiConnessiRuleEngine.getRate(cfg.DeveloperName, rule.SIAE_DeviceType__c, Decimal.valueOf(3), null, tariffs);
        System.assertNotEquals(null, rateFound, 'getRate should find the tariff for config CFG and device DEV');
        System.assertEquals(10, rateFound.setScale(0), 'Tariff amount should be 10');

        // Local reproduction of getQuantity logic to verify quantita used by engine
        Integer expectedQuantita = 1;
        if (String.isNotBlank(rule.SIAE_AttributeQuantity__c)) {
            Decimal q = SIAE_UTIL_DirittiConnessiRuleEngine.parseDecimal(attrs.get(rule.SIAE_AttributeQuantity__c));
            expectedQuantita = q != null ? q.intValue() : 0;
        } else if (String.isNotBlank(rule.SIAE_AttributeQuantityList__c)) {
            Decimal total = 0;
            for (String code : rule.SIAE_AttributeQuantityList__c.split(';')) {
                Decimal q2 = SIAE_UTIL_DirittiConnessiRuleEngine.parseDecimal(attrs.get(code.trim()));
                if (q2 != null) total += q2;
            }
            expectedQuantita = total.intValue();
        }

        // Reproduce calculateUnitsToApplyStandard locally
        Integer daUnita = rule.SIAE_ApplyFromUnit__c != null ? Integer.valueOf(rule.SIAE_ApplyFromUnit__c) : 1;
        Integer aUnita = rule.SIAE_ApplyToUnit__c != null ? Integer.valueOf(rule.SIAE_ApplyToUnit__c) : expectedQuantita;
        aUnita = Math.min(aUnita, expectedQuantita);
        Integer expectedUnitaDaApplicare = 0;
        if (daUnita <= expectedQuantita) {
            Integer tmp = aUnita - daUnita + 1;
            expectedUnitaDaApplicare = tmp <= 0 ? 0 : tmp;
        }

        System.debug('DIAG expectedQuantita=' + expectedQuantita + ', expectedUnitaDaApplicare=' + expectedUnitaDaApplicare);
        System.assertEquals(3, expectedQuantita, 'Expected quantita should be 3 from attrs');
        System.assertEquals(2, expectedUnitaDaApplicare, 'Expected unitaDaApplicare should be 2 for ApplyFrom=2 ApplyTo=4 and quantita=3');

        SIAE_DTO_DirittiConnessiResult.LicenzaDetail res =
            SIAE_UTIL_DirittiConnessiRuleEngine.evaluate(node, attrs, rules, tariffs, cfg);

        System.assertNotEquals(null, res, 'Result non deve essere null');
        System.assertEquals('line-2', res.orderItemId, 'orderItemId valorizzato');

        // Dovrebbe esserci almeno un dettaglio dispositivo
        System.assert(res.dettagliDispositivi.size() >= 1, 'Almeno un dettaglio dispositivo deve essere presente');

        // Verifichiamo importo calcolato coerente: tariffa 10 * unitaDaApplicare (2) = 20
        Decimal expectedLine = 20;
        Boolean matched = false;
        for (SIAE_DTO_DirittiConnessiResult.DispositivoDetail dd : res.dettagliDispositivi) {
            if (dd.tipoDispositivo == 'DEV') {
                // importoRiga arrotondato a 2 decimali
                System.assertEquals(expectedLine.setScale(2), dd.importoRiga.setScale(2), 'Importo riga atteso');
                matched = true;
            }
        }
        System.assert(matched, 'Dettaglio per device DEV trovato');
    }

    @IsTest
    static void testEvaluate_SubtotalePreScontoConScontoDC() {
        SIAE_DirittiConnessiRule__c rule = new SIAE_DirittiConnessiRule__c();
        rule.SIAE_ApplyFromUnit__c = 2;
        rule.SIAE_ApplyToUnit__c = 4;
        rule.SIAE_Attribute__c = 'QTY';
        rule.SIAE_Operator__c = 'EQ';
        rule.SIAE_ValueFrom__c = '3';
        rule.SIAE_AttributeQuantity__c = 'QTY';
        rule.SIAE_Action__c = 'TARIFFA_BASE';
        rule.SIAE_DeviceType__c = 'DEV';
        rule.SIAE_RevenueItemDC__c = 'R1';

        SIAE_DirittiConnessiTariffa__c t = new SIAE_DirittiConnessiTariffa__c();
        t.SIAE_ConfigName__c = 'CFG';
        t.SIAE_DeviceType__c = 'DEV';
        t.SIAE_Amount__c = 10;
        t.SIAE_BracketFrom__c = 0;
        t.SIAE_BracketTo__c = 999999;

        Map<String, String> attrs = new Map<String, String>{ 'QTY' => '3' };

        RCASalesTransaction.ItemNode node = buildNode('line-dc');
        node.discountDc = 0.20; // 20% sconto DC

        SIAE_DirittiConnessiConfig__mdt cfg = new SIAE_DirittiConnessiConfig__mdt();
        cfg.DeveloperName = 'CFG';

        SIAE_DTO_DirittiConnessiResult.LicenzaDetail res =
            SIAE_UTIL_DirittiConnessiRuleEngine.evaluate(
                node,
                attrs,
                new List<SIAE_DirittiConnessiRule__c>{ rule },
                new List<SIAE_DirittiConnessiTariffa__c>{ t },
                cfg
            );

        // tariffa 10 * 2 unità = 20 pre-sconto; con 20% -> 16 scontato
        System.assertEquals(20.00, res.subtotalePreSconto.setScale(2), 'Subtotale pre-sconto atteso 20');
        System.assertEquals(16.00, res.subtotale.setScale(2), 'Subtotale scontato atteso 16');
        System.assertEquals(4.00, (res.subtotalePreSconto - res.subtotale).setScale(2), 'Importo sconto DC atteso 4');
    }

    @IsTest
    static void test_enrichAcconciatori_and_shouldSkip() {
        Map<String, String> attrs = new Map<String, String>{
            'SIAE-ATTR-RADIO' => '1',
            'SIAE-ATTR-TV-UND40' => '1'
        };

        // enrichAcconciatori è @TestVisible
        SIAE_UTIL_DirittiConnessiRuleEngine.enrichAcconciatori(attrs);
        System.assertEquals('1', attrs.get('RadioPiuTv'), 'RadioPiuTv deve essere impostato quando radio e tv presenti');

        // costruiamo regola standalone radio base e verifichiamo il comportamento tramite evaluate (indiretto)
        SIAE_DirittiConnessiRule__c standalone = new SIAE_DirittiConnessiRule__c();
        standalone.SIAE_Action__c = 'TARIFFA_BASE';
        standalone.SIAE_RevenueItemDC__c = '0792'; // radio base
        standalone.SIAE_Operator__c = 'ALWAYS';
        standalone.SIAE_DeviceType__c = 'RADIO';

        SIAE_DirittiConnessiConfig__mdt cfg = new SIAE_DirittiConnessiConfig__mdt();
        cfg.DeveloperName = 'Acconciatori';

        // Tariffa placeholder per RADIO
        SIAE_DirittiConnessiTariffa__c tr = new SIAE_DirittiConnessiTariffa__c();
        tr.SIAE_ConfigName__c = 'Acconciatori';
        tr.SIAE_DeviceType__c = 'RADIO';
        tr.SIAE_Amount__c = 1;
        tr.SIAE_BracketFrom__c = 0;
        tr.SIAE_BracketTo__c = 999999;

        List<SIAE_DirittiConnessiRule__c> rules = new List<SIAE_DirittiConnessiRule__c>{ standalone };
        List<SIAE_DirittiConnessiTariffa__c> tariffs = new List<SIAE_DirittiConnessiTariffa__c>{ tr };

        RCASalesTransaction.ItemNode node = buildNode('line-3');

        SIAE_DTO_DirittiConnessiResult.LicenzaDetail resEval =
            SIAE_UTIL_DirittiConnessiRuleEngine.evaluate(node, attrs, rules, tariffs, cfg);

        // Se RadioPiuTv è presente la regola standalone radio base dovrebbe essere ignorata -> nessun dettaglio per revenue 0792
        Boolean hasRadioBase = false;
        for (SIAE_DTO_DirittiConnessiResult.DispositivoDetail dd : resEval.dettagliDispositivi) {
            if (dd.revenueItem == '0792') {
                hasRadioBase = true;
            }
        }
        System.assertEquals(false, hasRadioBase, 'La regola standalone Radio non deve produrre dettagli quando RadioPiuTv è attivo');
    }

    @IsTest
    static void testEvaluate_ComplexScenario() {
        // Copertura indiretta di calculateUnitsToApplyWithDeviceGroup, 
        // virtualRadioPiuTvExtraAttrs, operatori IN/EQ_TOTAL e tutte le Action.
        
        RCASalesTransaction.ItemNode node = buildNode('line-complex');
        SIAE_DirittiConnessiConfig__mdt cfg = new SIAE_DirittiConnessiConfig__mdt(DeveloperName = 'Acconciatori');

        Map<String, String> attrs = new Map<String, String>{
            'SIAE-ATTR-RADIO' => '1', 'SIAE-ATTR-TV-UND40' => '1',
            'ATTR_IN' => 'VAL1', 'ATTR_Q1' => '10', 'ATTR_Q2' => '5',
            'ATTR_QTY' => '5', 'ATTR_LTE' => '5', 'ATTR_GT' => '25', 'ATTR_BETWEEN' => '15'
        };

        List<SIAE_DirittiConnessiRule__c> rules = new List<SIAE_DirittiConnessiRule__c>();
        List<SIAE_DirittiConnessiTariffa__c> tariffs = new List<SIAE_DirittiConnessiTariffa__c>();

        // 1. EQ_TOTAL: Verifica somma attributi (10+5=15). Quantita di default = 1.
        rules.add(new SIAE_DirittiConnessiRule__c(
            SIAE_Operator__c = 'EQ_TOTAL', SIAE_AttributeQuantityList__c = 'ATTR_Q1; ATTR_Q2',
            SIAE_ValueFrom__c = '15', SIAE_Action__c = 'TARIFFA_BASE', SIAE_DeviceType__c = 'EQT'
        ));
        tariffs.add(new SIAE_DirittiConnessiTariffa__c(SIAE_ConfigName__c='Acconciatori', SIAE_DeviceType__c='EQT', SIAE_Amount__c=10, SIAE_BracketFrom__c=0));

        // 2. Device Group (G1) - Regola Base (Unità 1-5). ATTR_QTY = 5.
        rules.add(new SIAE_DirittiConnessiRule__c(
            SIAE_Operator__c = 'ALWAYS', SIAE_Action__c = 'TARIFFA_BASE', SIAE_DeviceType__c = 'DEV1',
            SIAE_DeviceGroupKey__c = 'G1', SIAE_ApplyFromUnit__c = 1, SIAE_ApplyToUnit__c = 5,
            SIAE_AttributeQuantity__c = 'ATTR_QTY'
        ));
        // 3. Device Group (G1) - Maggiorazione (Unità 6-10). ATTR_QTY = 5 -> Applicate unità 6-10.
        rules.add(new SIAE_DirittiConnessiRule__c(
            SIAE_Operator__c = 'ALWAYS', SIAE_Action__c = 'MAGGIORAZIONE_PCT', SIAE_ActionValue__c = 10,
            SIAE_DeviceType__c = 'DEV1', SIAE_DeviceGroupKey__c = 'G1',
            SIAE_ApplyFromUnit__c = 6, SIAE_ApplyToUnit__c = 10, SIAE_AttributeQuantity__c = 'ATTR_QTY'
        ));
        tariffs.add(new SIAE_DirittiConnessiTariffa__c(SIAE_ConfigName__c='Acconciatori', SIAE_DeviceType__c='DEV1', SIAE_Amount__c=100, SIAE_BracketFrom__c=0));

        // 4. IN + RIDUZIONE_PCT
        rules.add(new SIAE_DirittiConnessiRule__c(
            SIAE_Operator__c = 'IN', SIAE_Attribute__c = 'ATTR_IN', SIAE_ValueFrom__c = 'VAL1,VAL2',
            SIAE_Action__c = 'RIDUZIONE_PCT', SIAE_ActionValue__c = 20, SIAE_DeviceType__c = 'DEV2'
        ));
        // 5. LTE + MAGGIORAZIONE_FLAT
        rules.add(new SIAE_DirittiConnessiRule__c(
            SIAE_Operator__c = 'LTE', SIAE_Attribute__c = 'ATTR_LTE', SIAE_ValueFrom__c = '10',
            SIAE_Action__c = 'MAGGIORAZIONE_FLAT', SIAE_ActionValue__c = 50, SIAE_DeviceType__c = 'DEV2'
        ));
        // 6. GT + RIDUZIONE_FLAT
        rules.add(new SIAE_DirittiConnessiRule__c(
            SIAE_Operator__c = 'GT', SIAE_Attribute__c = 'ATTR_GT', SIAE_ValueFrom__c = '20',
            SIAE_Action__c = 'RIDUZIONE_FLAT', SIAE_ActionValue__c = 30, SIAE_DeviceType__c = 'DEV2'
        ));
        // 7. BETWEEN + MOLTIPLICATORE
        rules.add(new SIAE_DirittiConnessiRule__c(
            SIAE_Operator__c = 'BETWEEN', SIAE_Attribute__c = 'ATTR_BETWEEN', SIAE_ValueFrom__c = '10', SIAE_ValueTo__c = '20',
            SIAE_Action__c = 'MOLTIPLICATORE', SIAE_ActionValue__c = 1.5, SIAE_DeviceType__c = 'DEV2'
        ));
        tariffs.add(new SIAE_DirittiConnessiTariffa__c(SIAE_ConfigName__c='Acconciatori', SIAE_DeviceType__c='DEV2', SIAE_Amount__c=100, SIAE_BracketFrom__c=0));

        // 8. SCONTO_SUL_TOTALE_PCT
        rules.add(new SIAE_DirittiConnessiRule__c(
            SIAE_Operator__c = 'ALWAYS', SIAE_Action__c = 'SCONTO_SUL_TOTALE_PCT', SIAE_ActionValue__c = 10, SIAE_DeviceType__c = 'DISC'
        ));
        tariffs.add(new SIAE_DirittiConnessiTariffa__c(SIAE_ConfigName__c='Acconciatori', SIAE_DeviceType__c='DISC', SIAE_Amount__c=0, SIAE_BracketFrom__c=0));

        // 9. Skip Logic: Standalone Radio e Virtual Extra
        rules.add(new SIAE_DirittiConnessiRule__c(SIAE_Action__c = 'TARIFFA_BASE', SIAE_RevenueItemDC__c = '0792', SIAE_Operator__c = 'ALWAYS', SIAE_DeviceType__c = 'RADIO'));
        rules.add(new SIAE_DirittiConnessiRule__c(SIAE_Action__c = 'TARIFFA_BASE', SIAE_AttributeQuantity__c = 'RadioPiuTvRadioExtra', SIAE_Operator__c = 'ALWAYS', SIAE_DeviceType__c = 'VIRT'));

        SIAE_DTO_DirittiConnessiResult.LicenzaDetail res = SIAE_UTIL_DirittiConnessiRuleEngine.evaluate(node, attrs, rules, tariffs, cfg);

        System.assertNotEquals(null, res);
        Boolean foundR1 = false, foundR2 = false, foundSkip = false;
        for(SIAE_DTO_DirittiConnessiResult.DispositivoDetail dd : res.dettagliDispositivi) {
            if (dd.revenueItem == '0792' || dd.tipoDispositivo == 'VIRT') foundSkip = true;
            if (dd.tipoDispositivo == 'DEV1' && dd.importoRiga == 500) foundR1 = true; // Tariffa 100 * 5 unita
            if (dd.tipoDispositivo == 'DEV1' && dd.importoRiga == 50) foundR2 = true;  // Maggiorazione (100 * 10%) * 5 unita
        }
        System.assertEquals(false, foundSkip, 'Le regole standalone/virtuali devono essere saltate');
        System.assert(foundR1, 'R1 (Base) non trovata');
        System.assert(foundR2, 'R2 (PCT) non trovata');
    }

    @IsTest
    static void test_evaluate_SecondaryAttribute_and_EdgeCases() {
        RCASalesTransaction.ItemNode node = buildNode('line-edge');
        Map<String, String> attrs = new Map<String, String>{ 'MAIN' => '1', 'SEC' => 'VAL_B' };
        SIAE_DirittiConnessiRule__c rule = new SIAE_DirittiConnessiRule__c(
            SIAE_Attribute__c = 'MAIN', SIAE_Operator__c = 'ALWAYS', SIAE_SecondaryAttribute__c = 'SEC',
            SIAE_DeviceType__c = 'DEV', SIAE_Action__c = 'TARIFFA_BASE'
        );
        SIAE_DirittiConnessiTariffa__c tariff = new SIAE_DirittiConnessiTariffa__c(
            SIAE_ConfigName__c = 'CFG', SIAE_DeviceType__c = 'DEV', SIAE_SecondaryParameterValue__c = 'VAL_B',
            SIAE_BracketFrom__c = 0, SIAE_Amount__c = 500
        );
        SIAE_DirittiConnessiConfig__mdt cfg = new SIAE_DirittiConnessiConfig__mdt(DeveloperName = 'CFG');

        SIAE_DTO_DirittiConnessiResult.LicenzaDetail res = SIAE_UTIL_DirittiConnessiRuleEngine.evaluate(node, attrs, new List<SIAE_DirittiConnessiRule__c>{rule}, new List<SIAE_DirittiConnessiTariffa__c>{tariff}, cfg);
        System.assertEquals(500, res.dettagliDispositivi[0].importoRiga);
        
        // Copertura parseDecimal con virgola (metodo @TestVisible)
        System.assertEquals(10.5, SIAE_UTIL_DirittiConnessiRuleEngine.parseDecimal('10,5'));
    }

    @IsTest
    static void testCoverage_DirectMethods() {
        // 1. conditionMatches - Op IN, EQ_TOTAL, LTE, GT, BETWEEN, EQ (String)
        Map<String, String> attrs = new Map<String, String>{ 'A' => '10', 'B' => '20', 'STR' => 'Value' };
        
        SIAE_DirittiConnessiRule__c rIn = new SIAE_DirittiConnessiRule__c(SIAE_Operator__c = 'IN', SIAE_Attribute__c = 'STR', SIAE_ValueFrom__c = 'value,other');
        System.assert(SIAE_UTIL_DirittiConnessiRuleEngine.conditionMatches(rIn, attrs), 'IN should be case insensitive');
        
        SIAE_DirittiConnessiRule__c rTotal = new SIAE_DirittiConnessiRule__c(SIAE_Operator__c = 'EQ_TOTAL', SIAE_AttributeQuantityList__c = 'A; B', SIAE_ValueFrom__c = '30');
        System.assert(SIAE_UTIL_DirittiConnessiRuleEngine.conditionMatches(rTotal, attrs), 'EQ_TOTAL should sum A and B');
        
        SIAE_DirittiConnessiRule__c rLte = new SIAE_DirittiConnessiRule__c(SIAE_Operator__c = 'LTE', SIAE_Attribute__c = 'A', SIAE_ValueFrom__c = '10');
        System.assert(SIAE_UTIL_DirittiConnessiRuleEngine.conditionMatches(rLte, attrs), 'LTE match');
        
        SIAE_DirittiConnessiRule__c rGt = new SIAE_DirittiConnessiRule__c(SIAE_Operator__c = 'GT', SIAE_Attribute__c = 'A', SIAE_ValueFrom__c = '5');
        System.assert(SIAE_UTIL_DirittiConnessiRuleEngine.conditionMatches(rGt, attrs), 'GT match');
        
        SIAE_DirittiConnessiRule__c rBet = new SIAE_DirittiConnessiRule__c(SIAE_Operator__c = 'BETWEEN', SIAE_Attribute__c = 'A', SIAE_ValueFrom__c = '5', SIAE_ValueTo__c = '15');
        System.assert(SIAE_UTIL_DirittiConnessiRuleEngine.conditionMatches(rBet, attrs), 'BETWEEN match');

        SIAE_DirittiConnessiRule__c rEqStr = new SIAE_DirittiConnessiRule__c(SIAE_Operator__c = 'EQ', SIAE_Attribute__c = 'STR', SIAE_ValueFrom__c = 'VALUE');
        System.assert(SIAE_UTIL_DirittiConnessiRuleEngine.conditionMatches(rEqStr, attrs), 'EQ string match');

        // 2. calculateLineItemPrice - All Actions
        Decimal rate = 100;
        Integer qty = 1;
        SIAE_DirittiConnessiRule__c rAct = new SIAE_DirittiConnessiRule__c(SIAE_ActionValue__c = 10);
        
        rAct.SIAE_Action__c = 'MAGGIORAZIONE_PCT';
        System.assertEquals(10, SIAE_UTIL_DirittiConnessiRuleEngine.calculateLineItemPrice(rAct, rate, qty, 0, null, null, 0));
        
        rAct.SIAE_Action__c = 'MAGGIORAZIONE_FLAT';
        rAct.SIAE_ActionValue__c = 50;
        System.assertEquals(50, SIAE_UTIL_DirittiConnessiRuleEngine.calculateLineItemPrice(rAct, rate, qty, 0, null, null, 0));
        
        rAct.SIAE_Action__c = 'RIDUZIONE_PCT';
        rAct.SIAE_ActionValue__c = 25;
        System.assertEquals(75, SIAE_UTIL_DirittiConnessiRuleEngine.calculateLineItemPrice(rAct, rate, qty, 0, null, null, 0));
        
        rAct.SIAE_Action__c = 'RIDUZIONE_FLAT';
        rAct.SIAE_ActionValue__c = 30;
        System.assertEquals(-30, SIAE_UTIL_DirittiConnessiRuleEngine.calculateLineItemPrice(rAct, rate, qty, 0, null, null, 0));
        
        rAct.SIAE_Action__c = 'MOLTIPLICATORE';
        rAct.SIAE_ActionValue__c = 1.2;
        System.assertEquals(20, SIAE_UTIL_DirittiConnessiRuleEngine.calculateLineItemPrice(rAct, rate, qty, 0, null, null, 0), '100 * (1.2 - 1) * 1 = 20');
        
        rAct.SIAE_Action__c = 'SCONTO_SUL_TOTALE_PCT';
        rAct.SIAE_ActionValue__c = 10;
        System.assertEquals(-50, SIAE_UTIL_DirittiConnessiRuleEngine.calculateLineItemPrice(rAct, rate, qty, 0, null, null, 500));

        // 3. calculateUnitsToApplyWithDeviceGroup
        Map<String, Integer> consumed = new Map<String, Integer>();
        SIAE_DirittiConnessiRule__c rGrp = new SIAE_DirittiConnessiRule__c(SIAE_DeviceGroupKey__c = 'GRP', SIAE_ApplyFromUnit__c = 3, SIAE_ApplyToUnit__c = 5);
        // First call: qty 2 (1-2) -> 0 units in range 3-5
        System.assertEquals(0, SIAE_UTIL_DirittiConnessiRuleEngine.calculateUnitsToApplyWithDeviceGroup(rGrp, 2, consumed));
        // Second call: qty 4 (3-6) -> 3, 4, 5 are in range -> 3 units
        System.assertEquals(3, SIAE_UTIL_DirittiConnessiRuleEngine.calculateUnitsToApplyWithDeviceGroup(rGrp, 4, consumed));

        // 4. Tariffe Index & Thresholds
        List<SIAE_DirittiConnessiTariffa__c> tariffs = new List<SIAE_DirittiConnessiTariffa__c>{
            new SIAE_DirittiConnessiTariffa__c(SIAE_ConfigName__c='C', SIAE_DeviceType__c='D', SIAE_BracketFrom__c=0, SIAE_BracketTo__c=10, SIAE_Amount__c=50),
            new SIAE_DirittiConnessiTariffa__c(SIAE_ConfigName__c='C', SIAE_DeviceType__c='D', SIAE_BracketFrom__c=11, SIAE_BracketTo__c=20, SIAE_Amount__c=80)
        };
        System.assert(SIAE_UTIL_DirittiConnessiRuleEngine.buildTariffeIndex(tariffs).containsKey('C|D|NONE|0|10'));
        System.assertEquals(80, SIAE_UTIL_DirittiConnessiRuleEngine.getLastTreshold(tariffs, 'C', 'D', null).SIAE_Amount__c);
    }

    @IsTest
    static void testCoverage_SkipLogic() {
        SIAE_DirittiConnessiConfig__mdt cfg = new SIAE_DirittiConnessiConfig__mdt(DeveloperName = 'Acconciatori');
        Map<String, String> attrs = new Map<String, String>{ 'RadioPiuTv' => '1' };
        
        // Standalone Radio Base
        SIAE_DirittiConnessiRule__c rRadio = new SIAE_DirittiConnessiRule__c(SIAE_Action__c = 'TARIFFA_BASE', SIAE_RevenueItemDC__c = '0792');
        System.assert(SIAE_UTIL_DirittiConnessiRuleEngine.shouldSkipAcconciatoriStandaloneRadioTvRule(cfg, rRadio, attrs));
        
        // Standalone TV Base
        SIAE_DirittiConnessiRule__c rTv = new SIAE_DirittiConnessiRule__c(SIAE_Action__c = 'TARIFFA_BASE', SIAE_RevenueItemDC__c = '0793');
        System.assert(SIAE_UTIL_DirittiConnessiRuleEngine.shouldSkipAcconciatoriStandaloneRadioTvRule(cfg, rTv, attrs));
        
        // Virtual Extra Attributes
        SIAE_DirittiConnessiRule__c rVirt = new SIAE_DirittiConnessiRule__c(SIAE_AttributeQuantity__c = 'RadioPiuTvRadioExtra');
        System.assert(SIAE_UTIL_DirittiConnessiRuleEngine.shouldSkipAcconciatoriStandaloneRadioTvRule(cfg, rVirt, attrs));
        
        SIAE_DirittiConnessiRule__c rVirt2 = new SIAE_DirittiConnessiRule__c(SIAE_AttributeQuantity__c = 'RadioPiuTvTvExtra');
        System.assert(SIAE_UTIL_DirittiConnessiRuleEngine.shouldSkipAcconciatoriStandaloneRadioTvRule(cfg, rVirt2, attrs));
        
        SIAE_DirittiConnessiRule__c rVirt3 = new SIAE_DirittiConnessiRule__c(SIAE_AttributeQuantity__c = 'RadioPiuTvTvOvr40Count');
        System.assert(SIAE_UTIL_DirittiConnessiRuleEngine.shouldSkipAcconciatoriStandaloneRadioTvRule(cfg, rVirt3, attrs));
    }

    @IsTest
    static void testCoverage_HelperMethods() {
        // calculateUnitsToApplyStandard
        SIAE_DirittiConnessiRule__c rule = new SIAE_DirittiConnessiRule__c(SIAE_ApplyFromUnit__c = 5, SIAE_ApplyToUnit__c = 8);
        System.assertEquals(4, SIAE_UTIL_DirittiConnessiRuleEngine.calculateUnitsToApplyStandard(rule, 10));
        System.assertEquals(0, SIAE_UTIL_DirittiConnessiRuleEngine.calculateUnitsToApplyStandard(rule, 3));
        
        // getTresholdValue
        Map<String, String> attrs = new Map<String, String>{ 'A' => '10', 'B' => '20' };
        SIAE_DirittiConnessiRule__c rTres = new SIAE_DirittiConnessiRule__c(SIAE_AttributeTreshold__c = 'B');
        System.assertEquals(20, SIAE_UTIL_DirittiConnessiRuleEngine.getTresholdValue(rTres, attrs));
        
        // getQuantity
        SIAE_DirittiConnessiRule__c rQtyList = new SIAE_DirittiConnessiRule__c(SIAE_AttributeQuantityList__c = 'A; B');
        System.assertEquals(30, SIAE_UTIL_DirittiConnessiRuleEngine.getQuantity(rQtyList, attrs));
    }
    
    @IsTest
    static void testBarRistorantiFlatAudio_OnlyFlatRuleAndInstrumentId() {
        RCASalesTransaction.ItemNode node = buildNode('line-flat-audio');
        node.typeOfFlatRate = 'FLAT_AUDIO';
        node.periodicityCoefficient = 1;
        node.discountDc = 0;
        node.coeffMaggiorazioneMQ = 1.1;
        node.coeffAreeEsterne = 1;
    
        SIAE_DirittiConnessiConfig__mdt cfg =
            new SIAE_DirittiConnessiConfig__mdt(DeveloperName = 'Bar_Ristoranti');
    
        Map<String, String> attrs = new Map<String, String>{
            'SIAE-ATTR-QTA' => '516',
            'SIAE-ATTR-RADIO' => '2',
            'SIAE-ATTR-AUDIO' => '1'
        };
    
        SIAE_DirittiConnessiRule__c flatAudioRule = new SIAE_DirittiConnessiRule__c(
            SIAE_Operator__c = 'EQ',
            SIAE_Attribute__c = 'Num_FlatAudio',
            SIAE_ValueFrom__c = '1',
            SIAE_AttributeTreshold__c = 'SIAE-ATTR-QTA',
            SIAE_AttributeQuantity__c = 'Num_FlatAudio',
            SIAE_Action__c = 'TARIFFA_BASE',
            SIAE_DeviceType__c = 'FlatAudio',
            SIAE_RevenueItemDC__c = '0782',
            SIAE_RevenueItemType__c = 'LC',
            SIAE_IdInstrument__c = '3'
        );
    
        SIAE_DirittiConnessiRule__c radioRule = new SIAE_DirittiConnessiRule__c(
            SIAE_Operator__c = 'ALWAYS',
            SIAE_AttributeQuantity__c = 'SIAE-ATTR-RADIO',
            SIAE_Action__c = 'TARIFFA_BASE',
            SIAE_DeviceType__c = 'Radio',
            SIAE_RevenueItemDC__c = '0784',
            SIAE_RevenueItemType__c = 'LC',
            SIAE_IdInstrument__c = '6'
        );
    
        List<SIAE_DirittiConnessiRule__c> rules = new List<SIAE_DirittiConnessiRule__c>{
            flatAudioRule,
            radioRule
        };
    
        List<SIAE_DirittiConnessiTariffa__c> tariffs = new List<SIAE_DirittiConnessiTariffa__c>{
            new SIAE_DirittiConnessiTariffa__c(
                SIAE_ConfigName__c = 'Bar_Ristoranti',
                SIAE_DeviceType__c = 'FlatAudio',
                SIAE_BracketFrom__c = 0,
                SIAE_BracketTo__c = 75,
                SIAE_Amount__c = 163.95
            ),
            new SIAE_DirittiConnessiTariffa__c(
                SIAE_ConfigName__c = 'Bar_Ristoranti',
                SIAE_DeviceType__c = 'FlatAudio',
                SIAE_BracketFrom__c = 76,
                SIAE_BracketTo__c = 250,
                SIAE_Amount__c = 241.30
            ),
            new SIAE_DirittiConnessiTariffa__c(
                SIAE_ConfigName__c = 'Bar_Ristoranti',
                SIAE_DeviceType__c = 'FlatAudio',
                SIAE_BracketFrom__c = 251,
                SIAE_BracketTo__c = 500,
                SIAE_Amount__c = 384.60,
                SIAE_ExtraUnitSize__c = 100,
                SIAE_ExtraPercentage__c = 0.1
            ),
            new SIAE_DirittiConnessiTariffa__c(
                SIAE_ConfigName__c = 'Bar_Ristoranti',
                SIAE_DeviceType__c = 'Radio',
                SIAE_BracketFrom__c = 0,
                SIAE_BracketTo__c = 999999,
                SIAE_Amount__c = 90.50
            )
        };
    
        SIAE_DTO_DirittiConnessiResult.LicenzaDetail res =
            SIAE_UTIL_DirittiConnessiRuleEngine.evaluate(
                node,
                attrs,
                rules,
                tariffs,
                cfg
            );
    
        System.assertNotEquals(null, res, 'Result non deve essere null');
        System.assertEquals('line-flat-audio', res.orderItemId, 'orderItemId errato');
        System.assertEquals(1, res.dettagliDispositivi.size(), 'Con FLAT_AUDIO deve uscire solo la regola flat');
    
        SIAE_DTO_DirittiConnessiResult.DispositivoDetail dd =
            res.dettagliDispositivi[0];
    
        System.assertEquals('FlatAudio', dd.tipoDispositivo, 'DeviceType flat audio errato');
        System.assertEquals('0782', dd.revenueItem, 'Revenue item flat audio errato');
        System.assertEquals('LC', dd.revenueItemType, 'RevenueItemType errato');
        System.assertEquals('3', dd.instrumentId, 'InstrumentId deve essere copiato dalla regola DC');
        System.assertEquals(423.06, dd.importoRiga.setScale(2), 'Importo flat audio oltre 500 mq errato');
    }
    
    @IsTest
    static void testBarRistorantiFlatAudioVideo_OnlyFlatAvRule() {
        RCASalesTransaction.ItemNode node = buildNode('line-flat-av');
        node.typeOfFlatRate = 'FLAT_AUDIO_VIDEO';
        node.periodicityCoefficient = 1;
        node.discountDc = 0;
        node.coeffMaggiorazioneMQ = 1;
        node.coeffAreeEsterne = 1;
    
        SIAE_DirittiConnessiConfig__mdt cfg =
            new SIAE_DirittiConnessiConfig__mdt(DeveloperName = 'Bar_Ristoranti');
    
        Map<String, String> attrs = new Map<String, String>{
            'SIAE-ATTR-QTA' => '100',
            'SIAE-ATTR-RADIO' => '1',
            'SIAE-ATTR-AUDIO' => '1',
            'SIAE-ATTR-VIDEO' => '1'
        };
    
        SIAE_DirittiConnessiRule__c flatAvRule = new SIAE_DirittiConnessiRule__c(
            SIAE_Operator__c = 'EQ',
            SIAE_Attribute__c = 'Num_FlatAV',
            SIAE_ValueFrom__c = '1',
            SIAE_AttributeTreshold__c = 'SIAE-ATTR-QTA',
            SIAE_AttributeQuantity__c = 'Num_FlatAV',
            SIAE_Action__c = 'TARIFFA_BASE',
            SIAE_DeviceType__c = 'FlatAudioVideo',
            SIAE_RevenueItemDC__c = '0783',
            SIAE_RevenueItemType__c = 'LC',
            SIAE_IdInstrument__c = '4'
        );
    
        SIAE_DirittiConnessiRule__c audioRule = new SIAE_DirittiConnessiRule__c(
            SIAE_Operator__c = 'ALWAYS',
            SIAE_AttributeQuantity__c = 'SIAE-ATTR-AUDIO',
            SIAE_Action__c = 'TARIFFA_BASE',
            SIAE_DeviceType__c = 'Audio',
            SIAE_RevenueItemDC__c = '0786',
            SIAE_RevenueItemType__c = 'LC',
            SIAE_IdInstrument__c = '13'
        );
    
        List<SIAE_DirittiConnessiTariffa__c> tariffs = new List<SIAE_DirittiConnessiTariffa__c>{
            new SIAE_DirittiConnessiTariffa__c(
                SIAE_ConfigName__c = 'Bar_Ristoranti',
                SIAE_DeviceType__c = 'FlatAudioVideo',
                SIAE_BracketFrom__c = 0,
                SIAE_BracketTo__c = 250,
                SIAE_Amount__c = 608.40
            ),
            new SIAE_DirittiConnessiTariffa__c(
                SIAE_ConfigName__c = 'Bar_Ristoranti',
                SIAE_DeviceType__c = 'Audio',
                SIAE_BracketFrom__c = 0,
                SIAE_BracketTo__c = 999999,
                SIAE_Amount__c = 92.47
            )
        };
    
        SIAE_DTO_DirittiConnessiResult.LicenzaDetail res =
            SIAE_UTIL_DirittiConnessiRuleEngine.evaluate(
                node,
                attrs,
                new List<SIAE_DirittiConnessiRule__c>{ flatAvRule, audioRule },
                tariffs,
                cfg
            );
    
        System.assertEquals(1, res.dettagliDispositivi.size(), 'Con FLAT_AUDIO_VIDEO deve uscire solo la regola flat AV');
    
        SIAE_DTO_DirittiConnessiResult.DispositivoDetail dd =
            res.dettagliDispositivi[0];
    
        System.assertEquals('FlatAudioVideo', dd.tipoDispositivo, 'DeviceType flat AV errato');
        System.assertEquals('0783', dd.revenueItem, 'Revenue item flat AV errato');
        System.assertEquals('4', dd.instrumentId, 'InstrumentId flat AV errato');
        System.assertEquals(608.40, dd.importoRiga.setScale(2), 'Importo flat AV errato');
    }
    
    @IsTest
    static void testBarRistorantiWithoutFlat_DeviceRulesAreEvaluated() {
        RCASalesTransaction.ItemNode node = buildNode('line-no-flat');
        node.periodicityCoefficient = 1;
        node.discountDc = 0;
    
        SIAE_DirittiConnessiConfig__mdt cfg =
            new SIAE_DirittiConnessiConfig__mdt(DeveloperName = 'Bar_Ristoranti');
    
        Map<String, String> attrs = new Map<String, String>{
            'SIAE-ATTR-RADIO' => '1'
        };
    
        SIAE_DirittiConnessiRule__c radioRule = new SIAE_DirittiConnessiRule__c(
            SIAE_Operator__c = 'ALWAYS',
            SIAE_AttributeQuantity__c = 'SIAE-ATTR-RADIO',
            SIAE_Action__c = 'TARIFFA_BASE',
            SIAE_DeviceType__c = 'Radio',
            SIAE_RevenueItemDC__c = '0784',
            SIAE_RevenueItemType__c = 'LC',
            SIAE_IdInstrument__c = '6'
        );
    
        SIAE_DirittiConnessiTariffa__c tariff = new SIAE_DirittiConnessiTariffa__c(
            SIAE_ConfigName__c = 'Bar_Ristoranti',
            SIAE_DeviceType__c = 'Radio',
            SIAE_BracketFrom__c = 0,
            SIAE_BracketTo__c = 999999,
            SIAE_Amount__c = 90.50
        );
    
        SIAE_DTO_DirittiConnessiResult.LicenzaDetail res =
            SIAE_UTIL_DirittiConnessiRuleEngine.evaluate(
                node,
                attrs,
                new List<SIAE_DirittiConnessiRule__c>{ radioRule },
                new List<SIAE_DirittiConnessiTariffa__c>{ tariff },
                cfg
            );
    
        System.assertEquals(1, res.dettagliDispositivi.size(), 'Senza flat i dispositivi devono essere valutati');
        System.assertEquals('0784', res.dettagliDispositivi[0].revenueItem, 'Revenue item dispositivo errato');
        System.assertEquals('6', res.dettagliDispositivi[0].instrumentId, 'InstrumentId dispositivo errato');
    }
    
    @IsTest
    static void testGetRateExtraOltreScaglione500() {
        List<SIAE_DirittiConnessiTariffa__c> tariffs = new List<SIAE_DirittiConnessiTariffa__c>{
            new SIAE_DirittiConnessiTariffa__c(
                SIAE_ConfigName__c = 'Bar_Ristoranti',
                SIAE_DeviceType__c = 'FlatAudio',
                SIAE_BracketFrom__c = 0,
                SIAE_BracketTo__c = 75,
                SIAE_Amount__c = 163.95
            ),
            new SIAE_DirittiConnessiTariffa__c(
                SIAE_ConfigName__c = 'Bar_Ristoranti',
                SIAE_DeviceType__c = 'FlatAudio',
                SIAE_BracketFrom__c = 76,
                SIAE_BracketTo__c = 250,
                SIAE_Amount__c = 241.30
            ),
            new SIAE_DirittiConnessiTariffa__c(
                SIAE_ConfigName__c = 'Bar_Ristoranti',
                SIAE_DeviceType__c = 'FlatAudio',
                SIAE_BracketFrom__c = 251,
                SIAE_BracketTo__c = 500,
                SIAE_Amount__c = 384.60,
                SIAE_ExtraUnitSize__c = 100,
                SIAE_ExtraPercentage__c = 0.1
            )
        };
    
        Decimal rate = SIAE_UTIL_DirittiConnessiRuleEngine.getRate(
            'Bar_Ristoranti',
            'FlatAudio',
            516,
            null,
            tariffs
        );
    
        System.assertEquals(
            423.06,
            rate.setScale(2),
            'Per 516 mq deve applicare una tranche extra del 10% su 384.60'
        );
    }
    
    @IsTest
    static void testBarRistorantiFlatHelpersDirectCoverage() {
        SIAE_DirittiConnessiConfig__mdt cfg =
            new SIAE_DirittiConnessiConfig__mdt(DeveloperName = 'Bar_Ristoranti');
    
        RCASalesTransaction.ItemNode node = buildNode('line-flat-helper');
        node.typeOfFlatRate = 'FLAT_AUDIO';
        node.coeffAreeEsterne = 1.25;
        node.coeffMaggiorazioneMQ = 1.1;
    
        Map<String, String> attrs = new Map<String, String>();
    
        SIAE_UTIL_DirittiConnessiRuleEngine.enrichBarRistorantiFlatRateAttributes(
            node,
            attrs,
            cfg
        );
    
        System.assertEquals('1', attrs.get('Num_FlatAudio'), 'Num_FlatAudio deve essere valorizzato');
        System.assertEquals('0', attrs.get('Num_FlatAV'), 'Num_FlatAV deve restare 0');
    
        SIAE_DirittiConnessiRule__c flatRule = new SIAE_DirittiConnessiRule__c(
            SIAE_Action__c = 'TARIFFA_BASE',
            SIAE_DeviceType__c = 'FlatAudio'
        );
    
        SIAE_DirittiConnessiRule__c radioRule = new SIAE_DirittiConnessiRule__c(
            SIAE_Action__c = 'TARIFFA_BASE',
            SIAE_DeviceType__c = 'Radio'
        );
    
        System.assertEquals(
            false,
            SIAE_UTIL_DirittiConnessiRuleEngine.shouldSkipBarRistorantiRuleWhenFlatSelected(
                cfg,
                node,
                flatRule
            ),
            'La regola FlatAudio non deve essere saltata'
        );
    
        System.assertEquals(
            true,
            SIAE_UTIL_DirittiConnessiRuleEngine.shouldSkipBarRistorantiRuleWhenFlatSelected(
                cfg,
                node,
                radioRule
            ),
            'La regola Radio deve essere saltata quando è selezionata FLAT_AUDIO'
        );
    
        Decimal maggiorato = SIAE_UTIL_DirittiConnessiRuleEngine.applyBarRistorantiFlatMaggiorazioni(
            100,
            cfg,
            node,
            flatRule
        );
    
        System.assertEquals(
            125.00,
            maggiorato.setScale(2),
            'La maggiorazione flat Bar/Ristoranti deve applicare il coefficiente aree esterne'
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Regressione fix "-40% indebito su forfait puri" (Agriturismi / Affitti_brevi)
    // La riduzione era prodotta dai record Agr_/Aff_SoloRadio_Riduz40, rimossi in org.
    // Questi test replicano in-memory la config reale e presidiano il comportamento atteso.
    // ─────────────────────────────────────────────────────────────────────────

    // Regola base Agriturismi (forfait per scaglione posti letto), come da seed.
    private static SIAE_DirittiConnessiRule__c agriturismiBaseRule() {
        return new SIAE_DirittiConnessiRule__c(
            SIAE_LicenseConfig__c = 'Agriturismi',
            SIAE_Order__c = 10,
            SIAE_Attribute__c = 'ALWAYS',
            SIAE_Operator__c = 'ALWAYS',
            SIAE_DeviceType__c = 'PostiLetto',
            SIAE_Action__c = 'TARIFFA_BASE',
            SIAE_ApplyFromUnit__c = 1,
            SIAE_ApplyToUnit__c = 1,
            SIAE_AttributeTreshold__c = 'SIAE-ATTR-QTA',
            SIAE_RevenueItemDC__c = 'AGR_BASE'
        );
    }

    // Riduzione -40% "sola radio in luogo comune" (operatore EQ_EXCLUSIVE):
    // radio presente (SIAE-ATTR-RADIO >= 1) E nessun altro tipo di dispositivo (lista == 0).
    private static SIAE_DirittiConnessiRule__c agriturismiSolaRadioRule() {
        return new SIAE_DirittiConnessiRule__c(
            SIAE_LicenseConfig__c = 'Agriturismi',
            SIAE_Order__c = 20,
            SIAE_Attribute__c = 'SIAE-ATTR-RADIO',
            SIAE_Operator__c = 'EQ_EXCLUSIVE',
            SIAE_DeviceType__c = 'PostiLetto',
            SIAE_Action__c = 'SCONTO_SUL_TOTALE_PCT',
            SIAE_ActionValue__c = 40,
            SIAE_ApplyFromUnit__c = 1,
            SIAE_ApplyToUnit__c = 1,
            SIAE_AttributeTreshold__c = 'SIAE-ATTR-QTA',
            SIAE_AttributeQuantityList__c =
                'SIAE-ATTR-ALTOP-AUDIO;SIAE-ATTR-ALTOP-RADIO;SIAE-ATTR-ALTOP-VIDEO;' +
                'SIAE-ATTR-ALTOP-TV-UND40;SIAE-ATTR-ALTOP-TV-OVR40;SIAE-ATTR-AUDIO;' +
                'SIAE-ATTR-VIDEO;SIAE-ATTR-TV-UND40;SIAE-ATTR-TV-OVR40;' +
                'SIAE-ATTR-RADIOINSTORE;SIAE-ATTR-ALTOP-RADIOINSTORE'
        );
    }

    private static List<SIAE_DirittiConnessiTariffa__c> agriturismiTariffe() {
        return new List<SIAE_DirittiConnessiTariffa__c>{
            new SIAE_DirittiConnessiTariffa__c(
                SIAE_ConfigName__c = 'Agriturismi', SIAE_DeviceType__c = 'PostiLetto',
                SIAE_BracketFrom__c = 0, SIAE_BracketTo__c = 30, SIAE_Amount__c = 77.6),
            new SIAE_DirittiConnessiTariffa__c(
                SIAE_ConfigName__c = 'Agriturismi', SIAE_DeviceType__c = 'PostiLetto',
                SIAE_BracketFrom__c = 31, SIAE_BracketTo__c = 60, SIAE_Amount__c = 91.7),
            new SIAE_DirittiConnessiTariffa__c(
                SIAE_ConfigName__c = 'Agriturismi', SIAE_DeviceType__c = 'PostiLetto',
                SIAE_BracketFrom__c = 61, SIAE_BracketTo__c = null, SIAE_Amount__c = 120.03)
        };
    }

    private static List<SIAE_DirittiConnessiRule__c> agriturismiRuleSet() {
        // Ordine come nel seed: base (10) poi riduzione sola radio (20).
        return new List<SIAE_DirittiConnessiRule__c>{
            agriturismiBaseRule(), agriturismiSolaRadioRule()
        };
    }

    // A) 1 TV<40" annuale → forfait pieno 120,03: la riduzione "sola radio" NON deve scattare su TV.
    @IsTest
    static void testAgriturismi_SoloTv_NessunaRiduzione() {
        SIAE_DirittiConnessiConfig__mdt cfg =
            new SIAE_DirittiConnessiConfig__mdt(DeveloperName = 'Agriturismi');

        SIAE_DTO_DirittiConnessiResult.LicenzaDetail res =
            SIAE_UTIL_DirittiConnessiRuleEngine.evaluate(
                buildNode('agr-100-tv'),
                new Map<String, String>{ 'SIAE-ATTR-QTA' => '100', 'SIAE-ATTR-TV-UND40' => '1' },
                agriturismiRuleSet(),
                agriturismiTariffe(),
                cfg
            );

        System.assertEquals(120.03, res.subtotale.setScale(2),
            'Con 1 TV la riduzione sola-radio non deve applicarsi');
    }

    // A-bis) Sola radio (1) → riduzione -40% applicata: 120,03 x 0,6 = 72,02.
    @IsTest
    static void testAgriturismi_SolaRadio_ApplicaRiduzione40() {
        SIAE_DirittiConnessiConfig__mdt cfg =
            new SIAE_DirittiConnessiConfig__mdt(DeveloperName = 'Agriturismi');

        SIAE_DTO_DirittiConnessiResult.LicenzaDetail res =
            SIAE_UTIL_DirittiConnessiRuleEngine.evaluate(
                buildNode('agr-100-radio'),
                new Map<String, String>{ 'SIAE-ATTR-QTA' => '100', 'SIAE-ATTR-RADIO' => '1' },
                agriturismiRuleSet(),
                agriturismiTariffe(),
                cfg
            );

        System.assertEquals(72.02, res.subtotale.setScale(2),
            'Con la sola radio deve applicarsi la riduzione del 40%');
    }

    // A-ter) Più radio ma nessun altro dispositivo → è ancora "sola radio" → riduzione applicata.
    @IsTest
    static void testAgriturismi_PiuRadio_SolaRadio_ApplicaRiduzione() {
        SIAE_DirittiConnessiConfig__mdt cfg =
            new SIAE_DirittiConnessiConfig__mdt(DeveloperName = 'Agriturismi');

        SIAE_DTO_DirittiConnessiResult.LicenzaDetail res =
            SIAE_UTIL_DirittiConnessiRuleEngine.evaluate(
                buildNode('agr-100-3radio'),
                new Map<String, String>{ 'SIAE-ATTR-QTA' => '100', 'SIAE-ATTR-RADIO' => '3' },
                agriturismiRuleSet(),
                agriturismiTariffe(),
                cfg
            );

        System.assertEquals(72.02, res.subtotale.setScale(2),
            'Qualsiasi numero di radio (senza altri dispositivi) mantiene la riduzione');
    }

    // A-quater) Radio + altro dispositivo (es. TV) → NON è "sola radio" → nessuna riduzione.
    @IsTest
    static void testAgriturismi_RadioPiuAltroDispositivo_NessunaRiduzione() {
        SIAE_DirittiConnessiConfig__mdt cfg =
            new SIAE_DirittiConnessiConfig__mdt(DeveloperName = 'Agriturismi');

        SIAE_DTO_DirittiConnessiResult.LicenzaDetail res =
            SIAE_UTIL_DirittiConnessiRuleEngine.evaluate(
                buildNode('agr-100-radio-tv'),
                new Map<String, String>{ 'SIAE-ATTR-QTA' => '100', 'SIAE-ATTR-RADIO' => '1', 'SIAE-ATTR-TV-UND40' => '1' },
                agriturismiRuleSet(),
                agriturismiTariffe(),
                cfg
            );

        System.assertEquals(120.03, res.subtotale.setScale(2),
            'Radio insieme ad altro dispositivo non è uso esclusivo: nessuna riduzione');
    }

    // A-bis2) Singolo dispositivo non-radio (audio/video) non deve mai ridurre il forfait.
    @IsTest
    static void testAgriturismi_SingoloDispositivoNonRadio_NessunaRiduzione() {
        SIAE_DirittiConnessiConfig__mdt cfg =
            new SIAE_DirittiConnessiConfig__mdt(DeveloperName = 'Agriturismi');

        for (String dev : new List<String>{ 'SIAE-ATTR-AUDIO', 'SIAE-ATTR-VIDEO' }) {
            SIAE_DTO_DirittiConnessiResult.LicenzaDetail res =
                SIAE_UTIL_DirittiConnessiRuleEngine.evaluate(
                    buildNode('agr-' + dev),
                    new Map<String, String>{ 'SIAE-ATTR-QTA' => '100', dev => '1' },
                    agriturismiRuleSet(),
                    agriturismiTariffe(),
                    cfg
                );
            System.assertEquals(120.03, res.subtotale.setScale(2),
                'Forfait pieno atteso con 1 solo ' + dev + ' (non radio)');
        }
    }

    // B) Boundary sulle fasce posti letto (via getRate diretto e via evaluate).
    @IsTest
    static void testAgriturismi_FascePostiLetto_Boundary() {
        List<SIAE_DirittiConnessiTariffa__c> tar = agriturismiTariffe();

        System.assertEquals(77.6,   SIAE_UTIL_DirittiConnessiRuleEngine.getRate('Agriturismi','PostiLetto',30,  null,tar), 'fascia fino a 30');
        System.assertEquals(91.7,   SIAE_UTIL_DirittiConnessiRuleEngine.getRate('Agriturismi','PostiLetto',31,  null,tar), 'fascia 31-60 (boundary basso)');
        System.assertEquals(91.7,   SIAE_UTIL_DirittiConnessiRuleEngine.getRate('Agriturismi','PostiLetto',60,  null,tar), 'fascia 31-60 (boundary alto)');
        System.assertEquals(120.03, SIAE_UTIL_DirittiConnessiRuleEngine.getRate('Agriturismi','PostiLetto',61,  null,tar), 'fascia oltre 60 (boundary basso)');
        System.assertEquals(120.03, SIAE_UTIL_DirittiConnessiRuleEngine.getRate('Agriturismi','PostiLetto',500, null,tar), 'fascia oltre 60 (valore alto)');

        // evaluate sui due estremi
        SIAE_DirittiConnessiConfig__mdt cfg = new SIAE_DirittiConnessiConfig__mdt(DeveloperName = 'Agriturismi');
        SIAE_DTO_DirittiConnessiResult.LicenzaDetail r30 =
            SIAE_UTIL_DirittiConnessiRuleEngine.evaluate(buildNode('agr-30'),
                new Map<String,String>{ 'SIAE-ATTR-QTA' => '30' },
                new List<SIAE_DirittiConnessiRule__c>{ agriturismiBaseRule() }, tar, cfg);
        System.assertEquals(77.6, r30.subtotale.setScale(2), 'evaluate 30 posti letto');
    }

    // C) GUARD diretto su EQ_EXCLUSIVE: matcha solo con radio presente e nessun altro dispositivo.
    @IsTest
    static void testEqExclusive_ConditionMatches() {
        SIAE_DirittiConnessiRule__c riduz = agriturismiSolaRadioRule();

        System.assertEquals(true,
            SIAE_UTIL_DirittiConnessiRuleEngine.conditionMatches(riduz,
                new Map<String,String>{ 'SIAE-ATTR-RADIO' => '1' }),
            'Sola radio (1) → match');

        System.assertEquals(true,
            SIAE_UTIL_DirittiConnessiRuleEngine.conditionMatches(riduz,
                new Map<String,String>{ 'SIAE-ATTR-RADIO' => '5' }),
            'Solo radio (qualsiasi numero) → match');

        System.assertEquals(false,
            SIAE_UTIL_DirittiConnessiRuleEngine.conditionMatches(riduz,
                new Map<String,String>{ 'SIAE-ATTR-TV-UND40' => '1' }),
            '1 sola TV (nessuna radio) → NO match');

        System.assertEquals(false,
            SIAE_UTIL_DirittiConnessiRuleEngine.conditionMatches(riduz,
                new Map<String,String>{ 'SIAE-ATTR-RADIO' => '1', 'SIAE-ATTR-TV-UND40' => '1' }),
            'Radio + TV → NO match (non esclusivo)');

        System.assertEquals(false,
            SIAE_UTIL_DirittiConnessiRuleEngine.conditionMatches(riduz,
                new Map<String,String>{ 'SIAE-ATTR-RADIO' => '1', 'SIAE-ATTR-ALTOP-RADIO' => '1' }),
            'Radio + altoparlante supplementare → NO match (oltre la sola radio)');
    }

    // D) getQuantity per EQ_EXCLUSIVE ritorna il numero di radio (non la somma della lista "altri").
    @IsTest
    static void testEqExclusive_GetQuantity() {
        SIAE_DirittiConnessiRule__c riduz = agriturismiSolaRadioRule();

        System.assertEquals(1,
            SIAE_UTIL_DirittiConnessiRuleEngine.getQuantity(riduz,
                new Map<String,String>{ 'SIAE-ATTR-RADIO' => '1' }),
            'Quantità = numero radio (1)');

        System.assertEquals(3,
            SIAE_UTIL_DirittiConnessiRuleEngine.getQuantity(riduz,
                new Map<String,String>{ 'SIAE-ATTR-RADIO' => '3' }),
            'Quantità = numero radio (3), non la somma della lista');
    }

    // Regole Affitti_brevi 1 Stella: base + riduzione sola radio (EQ_EXCLUSIVE).
    private static SIAE_DirittiConnessiRule__c affittiBaseRule() {
        return new SIAE_DirittiConnessiRule__c(
            SIAE_LicenseConfig__c = 'Affitti_brevi',
            SIAE_Order__c = 10,
            SIAE_Attribute__c = 'SIAE-ATTR-FASCIA-TARIFFA',
            SIAE_Operator__c = 'EQ',
            SIAE_ValueFrom__c = '1 Stella',
            SIAE_DeviceType__c = '1 Stella',
            SIAE_Action__c = 'TARIFFA_BASE',
            SIAE_RevenueItemDC__c = 'AFF_BASE'
        );
    }

    private static SIAE_DirittiConnessiRule__c affittiSolaRadioRule() {
        return new SIAE_DirittiConnessiRule__c(
            SIAE_LicenseConfig__c = 'Affitti_brevi',
            SIAE_Order__c = 20,
            SIAE_Attribute__c = 'SIAE-ATTR-RADIO',
            SIAE_Operator__c = 'EQ_EXCLUSIVE',
            SIAE_DeviceType__c = '1 Stella',
            SIAE_Action__c = 'SCONTO_SUL_TOTALE_PCT',
            SIAE_ActionValue__c = 40,
            SIAE_ApplyFromUnit__c = 1,
            SIAE_ApplyToUnit__c = 1,
            SIAE_AttributeQuantityList__c =
                'SIAE-ATTR-ALTOP-AUDIO;SIAE-ATTR-ALTOP-RADIO;SIAE-ATTR-ALTOP-VIDEO;' +
                'SIAE-ATTR-ALTOP-TV-UND40;SIAE-ATTR-ALTOP-TV-OVR40;SIAE-ATTR-AUDIO;' +
                'SIAE-ATTR-VIDEO;SIAE-ATTR-TV-UND40;SIAE-ATTR-TV-OVR40;' +
                'SIAE-ATTR-RADIOINSTORE;SIAE-ATTR-ALTOP-RADIOINSTORE'
        );
    }

    private static SIAE_DirittiConnessiTariffa__c affittiTariffa1Stella() {
        return new SIAE_DirittiConnessiTariffa__c(
            SIAE_ConfigName__c = 'Affitti_brevi', SIAE_DeviceType__c = '1 Stella',
            SIAE_BracketFrom__c = 0, SIAE_BracketTo__c = 25, SIAE_Amount__c = 77.71);
    }

    // E) Affitti_brevi 1 TV → forfait pieno 77,71 (la riduzione sola-radio non scatta su TV).
    @IsTest
    static void testAffittiBrevi_SoloTv_NessunaRiduzione() {
        SIAE_DirittiConnessiConfig__mdt cfg =
            new SIAE_DirittiConnessiConfig__mdt(DeveloperName = 'Affitti_brevi');

        SIAE_DTO_DirittiConnessiResult.LicenzaDetail res =
            SIAE_UTIL_DirittiConnessiRuleEngine.evaluate(
                buildNode('aff-1s-tv'),
                new Map<String, String>{ 'SIAE-ATTR-FASCIA-TARIFFA' => '1 Stella', 'SIAE-ATTR-TV-UND40' => '1' },
                new List<SIAE_DirittiConnessiRule__c>{ affittiBaseRule(), affittiSolaRadioRule() },
                new List<SIAE_DirittiConnessiTariffa__c>{ affittiTariffa1Stella() }, cfg);

        System.assertEquals(77.71, res.subtotale.setScale(2),
            'Affitti_brevi 1 Stella con 1 TV: nessuna riduzione sola-radio');
    }

    // E-bis) Affitti_brevi sola radio → riduzione -40%: 77,71 x 0,6 = 46,63.
    @IsTest
    static void testAffittiBrevi_SolaRadio_ApplicaRiduzione40() {
        SIAE_DirittiConnessiConfig__mdt cfg =
            new SIAE_DirittiConnessiConfig__mdt(DeveloperName = 'Affitti_brevi');

        SIAE_DTO_DirittiConnessiResult.LicenzaDetail res =
            SIAE_UTIL_DirittiConnessiRuleEngine.evaluate(
                buildNode('aff-1s-radio'),
                new Map<String, String>{ 'SIAE-ATTR-FASCIA-TARIFFA' => '1 Stella', 'SIAE-ATTR-RADIO' => '1' },
                new List<SIAE_DirittiConnessiRule__c>{ affittiBaseRule(), affittiSolaRadioRule() },
                new List<SIAE_DirittiConnessiTariffa__c>{ affittiTariffa1Stella() }, cfg);

        System.assertEquals(46.63, res.subtotale.setScale(2),
            'Affitti_brevi 1 Stella sola radio: riduzione del 40% applicata');
    }

    // F) Stagionale (SPEC, implementazione rinviata): oggi la stagionalità è un coefficiente
    //    moltiplicativo (periodicityCoefficient). La tabella dedicata Agriturismi vale
    //    54,32 / 64,20 / 84,02 (≈ 70% dell'annuale). Con coeff 0,7 il forfait >60 (120,03) → 84,02.
    //    NB: un fix robusto deve garantire questi importi da RECORD dedicati
    //    (SIAE_SecondaryParameterValue__c='Stagionale'), non affidarsi al coefficiente passato.
    @IsTest
    static void testAgriturismi_Stagionale_SpecTabellaDedicata() {
        SIAE_DirittiConnessiConfig__mdt cfg =
            new SIAE_DirittiConnessiConfig__mdt(DeveloperName = 'Agriturismi');

        RCASalesTransaction.ItemNode node = buildNode('agr-stag-100');
        node.periodicityCoefficient = 0.7; // stagionalità come coefficiente (comportamento attuale)

        SIAE_DTO_DirittiConnessiResult.LicenzaDetail res =
            SIAE_UTIL_DirittiConnessiRuleEngine.evaluate(
                node,
                new Map<String,String>{ 'SIAE-ATTR-QTA' => '100', 'SIAE-ATTR-TV-UND40' => '1' },
                new List<SIAE_DirittiConnessiRule__c>{ agriturismiBaseRule() },
                agriturismiTariffe(), cfg);

        System.assertEquals(84.02, res.subtotale.setScale(2),
            'Stagionale >60: valore atteso 84,02 (tabella dedicata). Da presidiare con record dedicati.');
    }

    // =====================================================================
    // STAGIONALITA DIRITTI CONNESSI - tre coefficienti indipendenti per copertura
    //
    // La tariffa espone tre coefficienti DC indipendenti, uno per copertura:
    // - Annuale     -> SIAE_CoeffStagionalitaDC__c
    // - Semestrale  -> SIAE_CoeffStagionalitaDC_Semestrale__c
    // - Trimestrale -> SIAE_CoeffStagionalitaDC_Trimestrale__c
    // Ognuno sostituisce il coefficiente Diritti d'Autore SOLO per la propria
    // copertura; non c'è fallback tra un campo e l'altro. Se il campo della
    // copertura corrente è vuoto, resta il coefficiente Diritti d'Autore.
    // =====================================================================

    // Tariffe Agriturismi con il coefficiente DC Annuale al 70% su ogni scaglione.
    private static List<SIAE_DirittiConnessiTariffa__c> agriturismiTariffeAnnualeConCoeffDC() {
        List<SIAE_DirittiConnessiTariffa__c> tariffe = agriturismiTariffe();

        for (SIAE_DirittiConnessiTariffa__c t : tariffe) {
            t.SIAE_CoeffStagionalitaDC__c = 0.70;
        }

        return tariffe;
    }

    // Tariffe Agriturismi con i coefficienti DC Semestrale/Trimestrale valorizzati.
    private static List<SIAE_DirittiConnessiTariffa__c> agriturismiTariffeInfrannualeConCoeffDC(Decimal coeffSemestrale, Decimal coeffTrimestrale) {
        List<SIAE_DirittiConnessiTariffa__c> tariffe = agriturismiTariffe();

        for (SIAE_DirittiConnessiTariffa__c t : tariffe) {
            t.SIAE_CoeffStagionalitaDC_Semestrale__c = coeffSemestrale;
            t.SIAE_CoeffStagionalitaDC_Trimestrale__c = coeffTrimestrale;
        }

        return tariffe;
    }

    private static SIAE_DirittiConnessiTariffa__c tariffaConCoeffDC(Decimal coeffAnnuale, Decimal coeffSemestrale, Decimal coeffTrimestrale) {
        return new SIAE_DirittiConnessiTariffa__c(
            SIAE_ConfigName__c = 'Agriturismi',
            SIAE_DeviceType__c = 'PostiLetto',
            SIAE_BracketFrom__c = 0,
            SIAE_BracketTo__c = null,
            SIAE_Amount__c = 100,
            SIAE_CoeffStagionalitaDC__c = coeffAnnuale,
            SIAE_CoeffStagionalitaDC_Semestrale__c = coeffSemestrale,
            SIAE_CoeffStagionalitaDC_Trimestrale__c = coeffTrimestrale
        );
    }

    @IsTest
    static void testResolveSeasonality_Annuale_UsaCoeffTariffa() {
        RCASalesTransaction.ItemNode node = buildNode('cov-1');
        // Annuale con decorrenza a settembre: la PreHook ha già calcolato 1 * (13-9)/12.
        Decimal rateoAnnuale = (Decimal.valueOf(4) / 12);
        node.periodicityCoefficient = rateoAnnuale;
        node.typeCoverage = 'Annuale';

        System.assertEquals(0.70,
            SIAE_UTIL_DirittiConnessiRuleEngine.resolveSeasonalityCoefficient(node, tariffaConCoeffDC(0.70, null, null)),
            'Annuale: deve vincere il coefficiente DC Annuale della tariffa, non il rateo dei Diritti d Autore');
    }

    @IsTest
    static void testResolveSeasonality_Annuale_SenzaCoeff_MantieneRateoDirittiAutore() {
        RCASalesTransaction.ItemNode node = buildNode('cov-2');
        Decimal rateoAnnuale = (Decimal.valueOf(4) / 12);
        node.periodicityCoefficient = rateoAnnuale;
        node.typeCoverage = 'Annuale';

        System.assertEquals(rateoAnnuale,
            SIAE_UTIL_DirittiConnessiRuleEngine.resolveSeasonalityCoefficient(node, tariffaConCoeffDC(null, 0.60, 0.30)),
            'Annuale senza il proprio coefficiente DC: il rateo sui mesi residui deve sopravvivere, anche se Semestrale/Trimestrale sono valorizzati');
    }

    @IsTest
    static void testResolveSeasonality_Semestrale_UsaCoeffTariffa() {
        RCASalesTransaction.ItemNode node = buildNode('cov-3');
        node.periodicityCoefficient = 0.6; // coefficiente Diritti d'Autore Semestrale
        node.typeCoverage = 'Semestrale';

        System.assertEquals(0.60,
            SIAE_UTIL_DirittiConnessiRuleEngine.resolveSeasonalityCoefficient(node, tariffaConCoeffDC(0.70, 0.60, 0.30)),
            'Semestrale: deve vincere il coefficiente DC Semestrale della tariffa, non quello Annuale né lo 0,6 dei Diritti d Autore');
    }

    @IsTest
    static void testResolveSeasonality_Trimestrale_UsaCoeffTariffa() {
        RCASalesTransaction.ItemNode node = buildNode('cov-4');
        node.periodicityCoefficient = 0.4; // coefficiente Diritti d'Autore Trimestrale
        node.typeCoverage = 'Trimestrale';

        System.assertEquals(0.30,
            SIAE_UTIL_DirittiConnessiRuleEngine.resolveSeasonalityCoefficient(node, tariffaConCoeffDC(0.70, 0.60, 0.30)),
            'Trimestrale: deve vincere il coefficiente DC Trimestrale della tariffa, non quello Annuale né lo 0,4 dei Diritti d Autore');
    }

    @IsTest
    static void testResolveSeasonality_CampiIndipendenti_NonSiFannoFallbackTraLoro() {
        RCASalesTransaction.ItemNode node = buildNode('cov-5');
        SIAE_DirittiConnessiTariffa__c tariffa = tariffaConCoeffDC(0.70, null, null); // solo Annuale valorizzato

        node.periodicityCoefficient = 0.6;
        node.typeCoverage = 'Semestrale';
        System.assertEquals(0.6,
            SIAE_UTIL_DirittiConnessiRuleEngine.resolveSeasonalityCoefficient(node, tariffa),
            'Semestrale senza il proprio coefficiente: non deve ricadere su quello Annuale, resta il coefficiente Diritti d Autore');

        node.periodicityCoefficient = 0.4;
        node.typeCoverage = 'Trimestrale';
        System.assertEquals(0.4,
            SIAE_UTIL_DirittiConnessiRuleEngine.resolveSeasonalityCoefficient(node, tariffa),
            'Trimestrale senza il proprio coefficiente: non deve ricadere su quello Annuale, resta il coefficiente Diritti d Autore');
    }

    @IsTest
    static void testResolveSeasonality_CoperturaBlank_TrattataComeAnnuale() {
        RCASalesTransaction.ItemNode node = buildNode('cov-6');
        node.periodicityCoefficient = 1;
        node.typeCoverage = null;

        System.assertEquals(0.70,
            SIAE_UTIL_DirittiConnessiRuleEngine.resolveSeasonalityCoefficient(node, tariffaConCoeffDC(0.70, 0.60, 0.30)),
            'Copertura non valorizzata vale Annuale: si applica il coefficiente DC Annuale');

        node.typeCoverage = '   ';

        System.assertEquals(0.70,
            SIAE_UTIL_DirittiConnessiRuleEngine.resolveSeasonalityCoefficient(node, tariffaConCoeffDC(0.70, 0.60, 0.30)),
            'Copertura composta da soli spazi vale Annuale: si applica il coefficiente DC Annuale');
    }

    @IsTest
    static void testResolveSeasonality_Mensile_FuoriDallaRegola() {
        RCASalesTransaction.ItemNode node = buildNode('cov-7');
        node.periodicityCoefficient = 0.2; // coefficiente Diritti d'Autore Mensile
        node.typeCoverage = 'Mensile';

        System.assertEquals(0.2,
            SIAE_UTIL_DirittiConnessiRuleEngine.resolveSeasonalityCoefficient(node, tariffaConCoeffDC(0.70, 0.60, 0.30)),
            'Mensile non è gestita dalla stagionalità DC: resta il coefficiente Diritti d Autore');
    }

    @IsTest
    static void testResolveSeasonality_TariffaSenzaCoeff_NessunaRegressione() {
        RCASalesTransaction.ItemNode node = buildNode('cov-8');
        node.periodicityCoefficient = 0.6;
        node.typeCoverage = 'Semestrale';

        System.assertEquals(0.6,
            SIAE_UTIL_DirittiConnessiRuleEngine.resolveSeasonalityCoefficient(node, tariffaConCoeffDC(null, null, null)),
            'Tariffa senza alcun coefficiente DC: comportamento attuale invariato');

        System.assertEquals(0.6,
            SIAE_UTIL_DirittiConnessiRuleEngine.resolveSeasonalityCoefficient(node, null),
            'Nessuna tariffa risolta: comportamento attuale invariato');
    }

    @IsTest
    static void testResolveSeasonality_NodeNull() {
        System.assertEquals(1,
            SIAE_UTIL_DirittiConnessiRuleEngine.resolveSeasonalityCoefficient(null, tariffaConCoeffDC(null, 0.60, 0.30)),
            'Nodo assente: la copertura di default (Annuale) non ha un coefficiente DC valorizzato, resta neutro');
    }

    @IsTest
    static void testResolveSeasonality_NodeNull_ConCoeffAnnualeUsaCoeffTariffa() {
        System.assertEquals(0.70,
            SIAE_UTIL_DirittiConnessiRuleEngine.resolveSeasonalityCoefficient(null, tariffaConCoeffDC(0.70, 0.60, 0.30)),
            'Nodo assente: la copertura di default vale Annuale, quindi si applica il coefficiente DC Annuale se valorizzato');
    }

    // =====================================================================
    // STAGIONALITA DIRITTI CONNESSI - valori di configurazione reali
    //
    // - Agriturismi, Albergo, Affitti_brevi, Negozi: 70% su Semestrale e su
    //   Trimestrale, nessuna riduzione su Annuale (coefficiente lasciato vuoto).
    // - Acconciatori: 60% su Semestrale, 30% su Trimestrale, nessuna riduzione
    //   su Annuale.
    // =====================================================================

    private static SIAE_DirittiConnessiTariffa__c tariffaConCoeffPerCopertura(String configName, Decimal coeffSemestrale, Decimal coeffTrimestrale) {
        return new SIAE_DirittiConnessiTariffa__c(
            SIAE_ConfigName__c = configName,
            SIAE_DeviceType__c = 'Generico',
            SIAE_BracketFrom__c = 0,
            SIAE_BracketTo__c = null,
            SIAE_Amount__c = 100,
            SIAE_CoeffStagionalitaDC_Semestrale__c = coeffSemestrale,
            SIAE_CoeffStagionalitaDC_Trimestrale__c = coeffTrimestrale
        );
    }

    @IsTest
    static void testResolveSeasonality_Negozi_70PercentoSuSemestraleETrimestrale() {
        RCASalesTransaction.ItemNode node = buildNode('cov-negozi-1');
        SIAE_DirittiConnessiTariffa__c tariffa = tariffaConCoeffPerCopertura('Negozi', 0.70, 0.70);

        node.periodicityCoefficient = 0.6;
        node.typeCoverage = 'Semestrale';
        System.assertEquals(0.70,
            SIAE_UTIL_DirittiConnessiRuleEngine.resolveSeasonalityCoefficient(node, tariffa),
            'Negozi Semestrale: deve applicarsi il 70% del campo dedicato');

        node.periodicityCoefficient = 0.4;
        node.typeCoverage = 'Trimestrale';
        System.assertEquals(0.70,
            SIAE_UTIL_DirittiConnessiRuleEngine.resolveSeasonalityCoefficient(node, tariffa),
            'Negozi Trimestrale: deve applicarsi il 70% del campo dedicato');
    }

    @IsTest
    static void testResolveSeasonality_Acconciatori_60SemestraleE30Trimestrale() {
        RCASalesTransaction.ItemNode node = buildNode('cov-acconciatori-1');
        SIAE_DirittiConnessiTariffa__c tariffa = tariffaConCoeffPerCopertura('Acconciatori', 0.60, 0.30);

        node.periodicityCoefficient = 0.6;
        node.typeCoverage = 'Semestrale';
        System.assertEquals(0.60,
            SIAE_UTIL_DirittiConnessiRuleEngine.resolveSeasonalityCoefficient(node, tariffa),
            'Acconciatori Semestrale: deve applicarsi il 60% del campo dedicato');

        node.periodicityCoefficient = 0.4;
        node.typeCoverage = 'Trimestrale';
        System.assertEquals(0.30,
            SIAE_UTIL_DirittiConnessiRuleEngine.resolveSeasonalityCoefficient(node, tariffa),
            'Acconciatori Trimestrale: deve applicarsi il 30% del campo dedicato');
    }

    @IsTest
    static void testResolveRate_EsponeIlRecordCheHaFattoMatch() {
        List<SIAE_DirittiConnessiTariffa__c> tar = agriturismiTariffeAnnualeConCoeffDC();

        SIAE_UTIL_DirittiConnessiRuleEngine.RateResolution match =
            SIAE_UTIL_DirittiConnessiRuleEngine.resolveRate('Agriturismi', 'PostiLetto', 45, null, tar);

        System.assertNotEquals(null, match, 'Lo scaglione 31-60 deve fare match su 45');
        System.assertEquals(91.7, match.amount.setScale(2), 'Importo dello scaglione 31-60');
        System.assertEquals(0.70, match.tariffa.SIAE_CoeffStagionalitaDC__c,
            'Il record tariffa deve restare accessibile per leggere il coefficiente DC Annuale');

        System.assertEquals(null,
            SIAE_UTIL_DirittiConnessiRuleEngine.resolveRate('Agriturismi', 'Inesistente', 45, null, tar),
            'Device type senza tariffe: nessuna risoluzione');
    }

    // Agriturismi >60 posti letto: annuale 120,03 -> stagionale 84,02.
    // Il 70% arriva dal coefficiente DC Semestrale della tariffa mentre il nodo
    // porta lo 0,6 dei Diritti d'Autore: è la prova che il coefficiente DC
    // sostituisce quello DDA e non lo moltiplica.
    @IsTest
    static void testEvaluate_Semestrale_CoeffDCSostituisceQuelloDirittiAutore() {
        SIAE_DirittiConnessiConfig__mdt cfg =
            new SIAE_DirittiConnessiConfig__mdt(DeveloperName = 'Agriturismi');

        RCASalesTransaction.ItemNode node = buildNode('agr-stag-dc');
        node.periodicityCoefficient = 0.6;
        node.typeCoverage = 'Semestrale';

        SIAE_DTO_DirittiConnessiResult.LicenzaDetail res =
            SIAE_UTIL_DirittiConnessiRuleEngine.evaluate(
                node,
                new Map<String,String>{ 'SIAE-ATTR-QTA' => '100' },
                new List<SIAE_DirittiConnessiRule__c>{ agriturismiBaseRule() },
                agriturismiTariffeInfrannualeConCoeffDC(0.70, 0.35), cfg);

        System.assertEquals(84.02, res.subtotale.setScale(2),
            'Semestrale: 120,03 * 0,70 = 84,02 con il coefficiente DC Semestrale preso dalla tariffa');
    }

    @IsTest
    static void testEvaluate_Annuale_UsaCoeffTariffa() {
        SIAE_DirittiConnessiConfig__mdt cfg =
            new SIAE_DirittiConnessiConfig__mdt(DeveloperName = 'Agriturismi');

        RCASalesTransaction.ItemNode node = buildNode('agr-annuale-dc');
        node.periodicityCoefficient = 1;
        node.typeCoverage = 'Annuale';

        SIAE_DTO_DirittiConnessiResult.LicenzaDetail res =
            SIAE_UTIL_DirittiConnessiRuleEngine.evaluate(
                node,
                new Map<String,String>{ 'SIAE-ATTR-QTA' => '100' },
                new List<SIAE_DirittiConnessiRule__c>{ agriturismiBaseRule() },
                agriturismiTariffeAnnualeConCoeffDC(), cfg);

        System.assertEquals(84.02, res.subtotale.setScale(2),
            'Annuale: 120,03 * 0,70 = 84,02 con il coefficiente DC Annuale preso dalla tariffa');
    }

    @IsTest
    static void testEvaluate_Annuale_SenzaCoeffDC_MantieneImportoPieno() {
        SIAE_DirittiConnessiConfig__mdt cfg =
            new SIAE_DirittiConnessiConfig__mdt(DeveloperName = 'Agriturismi');

        RCASalesTransaction.ItemNode node = buildNode('agr-annuale-no-dc');
        node.periodicityCoefficient = 1;
        node.typeCoverage = 'Annuale';

        SIAE_DTO_DirittiConnessiResult.LicenzaDetail res =
            SIAE_UTIL_DirittiConnessiRuleEngine.evaluate(
                node,
                new Map<String,String>{ 'SIAE-ATTR-QTA' => '100' },
                new List<SIAE_DirittiConnessiRule__c>{ agriturismiBaseRule() },
                agriturismiTariffe(), cfg);

        System.assertEquals(120.03, res.subtotale.setScale(2),
            'Annuale senza coefficiente DC sulla tariffa: importo pieno invariato');
    }

    // Il coefficiente DC deve entrare anche nel pre-sconto, altrimenti
    // SIAE_TotalDiscountCADC__c (calcolato come preSconto - subtotale) esce sbagliato.
    @IsTest
    static void testEvaluate_Semestrale_CoeffDCAncheNelPreSconto() {
        SIAE_DirittiConnessiConfig__mdt cfg =
            new SIAE_DirittiConnessiConfig__mdt(DeveloperName = 'Agriturismi');

        RCASalesTransaction.ItemNode node = buildNode('agr-sconto-dc');
        node.periodicityCoefficient = 0.6;
        node.typeCoverage = 'Semestrale';
        node.discountDc = 0.10;

        SIAE_DTO_DirittiConnessiResult.LicenzaDetail res =
            SIAE_UTIL_DirittiConnessiRuleEngine.evaluate(
                node,
                new Map<String,String>{ 'SIAE-ATTR-QTA' => '100' },
                new List<SIAE_DirittiConnessiRule__c>{ agriturismiBaseRule() },
                agriturismiTariffeInfrannualeConCoeffDC(0.70, 0.35), cfg);

        System.assertEquals(84.02, res.subtotalePreSconto.setScale(2),
            'Pre-sconto: 120,03 * 0,70 = 84,02');
        System.assertEquals(75.62, res.subtotale.setScale(2),
            'Post-sconto: 120,03 * 0,70 * 0,90 = 75,62');
        System.assertEquals(8.40, (res.subtotalePreSconto - res.subtotale).setScale(2),
            'Lo sconto CA DC deve calcolarsi su importi già stagionalizzati');
    }
}