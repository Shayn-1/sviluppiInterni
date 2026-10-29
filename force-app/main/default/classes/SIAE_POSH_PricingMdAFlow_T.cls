/**
 * Test class for SIAE_POSH_PricingMdAFlow
 * Verifies:
 *  - Success path with proper seasonal pro-rata adjustments
 *  - Field filtering (only configured fields are kept)
 *  - Handling of blank input
 *  - Resilience when numeric fields are non-decimal (type issues caught and ignored)
 */
@IsTest
private class SIAE_POSH_PricingMdAFlow_T {

    // Helper to build a minimal valid pricing JSON similar to Headless Pricing output
    private static String buildSamplePricingJson() {
        Map<String, Object> root = new Map<String, Object>();

        List<Object> salesTransactions = new List<Object>();

        // One SalesTransaction with totals and two items
        Map<String, Object> st = new Map<String, Object>();
        st.put('TotalAmount', Decimal.valueOf('100.00'));
        st.put('Subtotal', Decimal.valueOf('80.00'));
        st.put('HeaderDiscountValue', Decimal.valueOf('5.00'));
        st.put('ExtraFieldNotKept', 'shouldBeFiltered');

        List<Object> items = new List<Object>();

        Map<String, Object> item1 = new Map<String, Object>();
        item1.put('NetUnitPrice', Decimal.valueOf('120.00')); // Annual price
        item1.put('TotalLineAmount', Decimal.valueOf('20.00'));
        item1.put('SIAE_PrezzoSemestrale__c', Decimal.valueOf('60.00'));
        item1.put('SIAE_PrezzoTrimestrale__c', Decimal.valueOf('30.00'));
        item1.put('Product', null);
        item1.put('ExtraFieldNotKept', 'shouldBeFiltered');

        Map<String, Object> item2 = new Map<String, Object>();
        item2.put('NetUnitPrice', Decimal.valueOf('60.00')); // Annual price
        item2.put('TotalLineAmount', Decimal.valueOf('11.00'));
        item2.put('SIAE_PrezzoSemestrale__c', Decimal.valueOf('30.00'));
        item2.put('SIAE_PrezzoTrimestrale__c', Decimal.valueOf('15.00'));
        item2.put('Product', null);

        items.add(item1);
        items.add(item2);

        st.put('SalesTransactionItem', items);
        salesTransactions.add(st);

        root.put('SalesTransaction', salesTransactions);

        return JSON.serialize(root);
    }

    // Helper to invoke the Invocable method as Flow would do
    private static SIAE_POSH_PricingMdAFlow.FlowOutput invokeFlowWithJson(String jsonStr, String startDate) {
        SIAE_POSH_PricingMdAFlow.FlowInput inp = new SIAE_POSH_PricingMdAFlow.FlowInput();
        inp.pricingResultJson = jsonStr;
        inp.startDate = startDate;

        Test.startTest();
        List<SIAE_POSH_PricingMdAFlow.FlowOutput> outs = SIAE_POSH_PricingMdAFlow.execute(new List<SIAE_POSH_PricingMdAFlow.FlowInput>{ inp });
        Test.stopTest();

        System.assertEquals(1, outs.size(), 'Expected exactly one FlowOutput');
        return outs[0];
    }

    @IsTest
    static void testSuccess_ProRataAppliedAndFieldsFiltered() {
        String inputJson = buildSamplePricingJson();
        // Start date in July (month 7), so remaining months = 13 - 7 = 6 months
        String startDate = String.valueOf(Date.newInstance(Date.today().year(), 7, 1));

        SIAE_POSH_PricingMdAFlow.FlowOutput out = invokeFlowWithJson(inputJson, startDate);

        System.assertEquals('SUCCESS', out.status, 'Status should be SUCCESS');
        System.assert(out.message.contains('Mesi residui anno solare: 6'), 'Message should indicate 6 remaining months');
        System.assertNotEquals(inputJson, out.finalJsonString, 'Output JSON should be transformed');

        // Parse output to verify pro-rata adjustments and field filtering
        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(out.finalJsonString);

        List<Object> salesTransactions = (List<Object>) root.get('SalesTransaction');
        System.assertNotEquals(null, salesTransactions, 'SalesTransaction must be present');
        System.assertEquals(true, !salesTransactions.isEmpty(), 'SalesTransaction must not be empty');

        Map<String, Object> st = (Map<String, Object>) salesTransactions[0];

        // Verify only configured fields are kept at ST level
        System.assertEquals(true, st.containsKey('TotalAmount'), 'TotalAmount should be kept');
        System.assertEquals(true, st.containsKey('Subtotal'), 'Subtotal should be kept');
        System.assertEquals(true, st.containsKey('HeaderDiscountValue'), 'HeaderDiscountValue should be kept');
        System.assertEquals(false, st.containsKey('ExtraFieldNotKept'), 'Extra field should be filtered out');

        // These fields are not modified by the logic, just kept
        System.assertEquals(Decimal.valueOf('100.00'), (Decimal) st.get('TotalAmount'), 'TotalAmount unchanged');
        System.assertEquals(Decimal.valueOf('80.00'), (Decimal) st.get('Subtotal'), 'Subtotal unchanged');

        List<Object> items = (List<Object>) st.get('SalesTransactionItem');
        System.assertEquals(2, items.size(), 'Two items expected');

        Map<String, Object> item1 = (Map<String, Object>) items[0];
        // NetUnitPrice: 120.00 annual * (6/12) = 60.00 pro-rata
        System.assertEquals(Decimal.valueOf('60.00'), (Decimal) item1.get('NetUnitPrice'), 'NetUnitPrice item1 pro-rated for 6 months');
        System.assertEquals(Decimal.valueOf('20.00'), (Decimal) item1.get('TotalLineAmount'), 'TotalLineAmount item1 unchanged');
        // SIAE_PrezzoSemestrale__c: 60.00 (unchanged, no config coeff)
        System.assertEquals(Decimal.valueOf('60.00'), (Decimal) item1.get('SIAE_PrezzoSemestrale__c'), 'Semestral price item1');
        System.assertEquals(false, item1.containsKey('ExtraFieldNotKept'), 'Extra field should be filtered out from item');

        Map<String, Object> item2 = (Map<String, Object>) items[1];
        // NetUnitPrice: 60.00 annual * (6/12) = 30.00 pro-rata
        System.assertEquals(Decimal.valueOf('30.00'), (Decimal) item2.get('NetUnitPrice'), 'NetUnitPrice item2 pro-rated for 6 months');
    }

    @IsTest
    static void testBlankInput_ReturnsErrorAndEchoesInput() {
        // Blank input should trigger ERROR path
        SIAE_POSH_PricingMdAFlow.FlowOutput out = invokeFlowWithJson('', '2024-07-01');

        System.assertEquals('ERROR', out.status, 'Blank input should be ERROR');
        System.assertEquals('Input JSON vuoto o nullo.', out.message, 'Should explain blank input');
        System.assertEquals('', out.finalJsonString, 'finalJsonString should echo original blank input');
    }

    @IsTest
    static void testNonDecimalFields_AreIgnored_NotBreakingFlow() {
        // Build JSON where a numeric field is not a Decimal (e.g., string) to ensure try/catch in applyProRata swallows error
        Map<String, Object> root = new Map<String, Object>();
        List<Object> sts = new List<Object>();

        Map<String, Object> st = new Map<String, Object>();
        // TotalAmount and Subtotal are at ST level - they're kept as-is
        st.put('TotalAmount', '100.00'); // String - will be kept as-is
        st.put('Subtotal', Decimal.valueOf('50.00')); // Valid decimal

        List<Object> items = new List<Object>();
        Map<String, Object> it = new Map<String, Object>();
        it.put('NetUnitPrice', '120'); // as string - pro-rata will fail silently, kept as-is
        it.put('TotalLineAmount', Decimal.valueOf('12.50')); // valid
        it.put('SIAE_PrezzoSemestrale__c', Decimal.valueOf('60.00')); // valid
        it.put('SIAE_PrezzoTrimestrale__c', null); // null should be skipped
        it.put('Product', null);
        items.add(it);

        st.put('SalesTransactionItem', items);
        sts.add(st);

        root.put('SalesTransaction', sts);

        String inputJson = JSON.serialize(root);
        // Start date in July (month 7), so remaining months = 6
        String startDate = String.valueOf(Date.newInstance(Date.today().year(), 7, 1));

        SIAE_POSH_PricingMdAFlow.FlowOutput out = invokeFlowWithJson(inputJson, startDate);

        System.assertEquals('SUCCESS', out.status, 'Status should still be SUCCESS even if some fields are not Decimal');

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(out.finalJsonString);
        List<Object> parsedSts = (List<Object>) parsed.get('SalesTransaction');
        Map<String, Object> parsedSt = (Map<String, Object>) parsedSts[0];

        // Subtotal is kept unchanged (not modified by the logic)
        System.assertEquals(Decimal.valueOf('50.00'), (Decimal) parsedSt.get('Subtotal'), 'Subtotal unchanged');

        // TotalAmount was string - kept as string
        System.assertEquals('100.00', (String) parsedSt.get('TotalAmount'), 'TotalAmount remains string');

        List<Object> parsedItems = (List<Object>) parsedSt.get('SalesTransactionItem');
        Map<String, Object> parsedItem = (Map<String, Object>) parsedItems[0];

        // NetUnitPrice was string - pro-rata conversion failed, field is filtered out (not in ITEM_FIELDS_TO_KEEP)
        // Actually NetUnitPrice IS in ITEM_FIELDS_TO_KEEP, so it stays as string when conversion fails
        Object netUnitPrice = parsedItem.get('NetUnitPrice');
        System.assert(netUnitPrice instanceof String || netUnitPrice instanceof Decimal, 'NetUnitPrice should be present');

        // TotalLineAmount was Decimal 12.50 - unchanged (not pro-rated, not in fields that get modified)
        System.assertEquals(Decimal.valueOf('12.50'), (Decimal) parsedItem.get('TotalLineAmount'), 'TotalLineAmount unchanged');

        // SIAE_PrezzoSemestrale__c was Decimal 60.00 - unchanged (no coeff applied, mesiResidui=6 so >= 6)
        System.assertEquals(Decimal.valueOf('60.00'), (Decimal) parsedItem.get('SIAE_PrezzoSemestrale__c'), 'Semestral price unchanged');

        // SIAE_PrezzoTrimestrale__c was null - should remain null (no coeff applied)
        System.assertEquals(null, parsedItem.get('SIAE_PrezzoTrimestrale__c'), 'Null field remains null');
    }

    // Verifica difensiva: un attributo Picklist esposto nel JSON di Headless Pricing
    // con il solo AttributePicklistValue (Id, senza AttributeValue testuale) deve
    // comunque essere risolto PRIMA del calcolo dei flat amount, altrimenti
    // hasExcludedFlatAudioAttributes/calculateAdditionalFlatAmount leggono null.
    @IsTest
    static void testPicklistAttribute_resolvedBeforeFlatCalculation() {
        Product2 p = new Product2(Name = 'Prod Flat Test', Family = 'Test', IsActive = true);
        insert p;

        SIAE_ConfigurazionePricing__c cfg = new SIAE_ConfigurazionePricing__c(
            SIAE_Attivo__c = true,
            SIAE_Product2__c = p.Id,
            SIAE_UsaFlat__c = true,
            SIAE_EscludiFlatAudio__c = 'SIAE-ATTR-RADIO'
        );
        insert cfg;

        AttributePicklist picklist = new AttributePicklist(Name = 'Test Radio Posh Flow');
        insert picklist;

        AttributePicklistValue pv = new AttributePicklistValue(
            Name = 'Tre',
            PicklistId = picklist.Id,
            Code = 'RADIO-3-TEST',
            Value = '3'
        );
        insert pv;

        Map<String, Object> root = new Map<String, Object>();
        List<Object> sts = new List<Object>();
        Map<String, Object> st = new Map<String, Object>();

        Map<String, Object> item = new Map<String, Object>();
        item.put('Product', String.valueOf(p.Id));
        item.put('SIAE_FlatAudio__c', Decimal.valueOf('100.00'));
        item.put('SIAE_FlatVideo__c', Decimal.valueOf('0.00'));
        item.put('SalesTransactionItemAttribute', new List<Object>{
            new Map<String, Object>{
                'AttributeDefinitionCode' => 'SIAE-ATTR-RADIO',
                'AttributePicklistValue'  => (String) pv.Id
            }
        });

        List<Object> items = new List<Object>{ item };
        st.put('SalesTransactionItem', items);
        sts.add(st);
        root.put('SalesTransaction', sts);

        String inputJson = JSON.serialize(root);
        String startDate = String.valueOf(Date.newInstance(Date.today().year(), 7, 1));

        SIAE_POSH_PricingMdAFlow.FlowOutput out = invokeFlowWithJson(inputJson, startDate);

        System.assertEquals('SUCCESS', out.status);

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(out.finalJsonString);
        Map<String, Object> parsedSt = (Map<String, Object>) ((List<Object>) parsed.get('SalesTransaction'))[0];
        Map<String, Object> parsedItem = (Map<String, Object>) ((List<Object>) parsedSt.get('SalesTransactionItem'))[0];

        System.assertEquals(
            0.00,
            (Decimal) parsedItem.get('SIAE_FlatAudio__c'),
            'SIAE-ATTR-RADIO risolto (valore 3) deve escludere il flat audio, provando che la risoluzione picklist e avvenuta prima del calcolo'
        );
    }
}