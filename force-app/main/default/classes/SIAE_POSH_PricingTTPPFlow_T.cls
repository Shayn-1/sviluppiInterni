@isTest
private class SIAE_POSH_PricingTTPPFlow_T {

    private static final String PRICED_JSON = '{"SalesTransaction": [{'
        + '"PriceBooks": "PB1", "HeaderDiscountValue": 0, "TotalAmount": 1, "Subtotal": 1, "GrandTotalAmount": 1,'
        + '"SIAE_PriceDetails__c": "{\\"lineItems\\":[{\\"lineItemId\\":\\"LI1\\"}]}",'
        + '"SalesTransactionItem": ['
        + '{"LineItem": "LI1", "Product": "P1", "ItemProductCode": "FP", "LineItemQuantity": "1",'
        + ' "NetUnitPrice": 25, "TotalLineAmount": 25, "SIAE_TotalDA__c": 20, "SIAE_DirittiConnessi__c": 5,'
        + ' "SIAE_TotalTaxDA__c": 4.4, "SIAE_TotalTaxDC__c": 1.1,'
        + ' "SIAE_PaymentItems__c": "{\\"paymentItems\\":[{\\"type\\":\\"DDA\\"}]}",'
        + ' "SIAE_TotalDA_I__c": 16, "SalesTransactionItemAttribute": []},'
        + '{"LineItem": "LI2", "TotalLineAmount": 30.005}]}]}';

    private static Map<String, Object> firstTransaction(Map<String, Object> root) {
        return (Map<String, Object>) ((List<Object>) root.get('SalesTransaction'))[0];
    }

    private static Map<String, Object> firstItem(Map<String, Object> root) {
        return (Map<String, Object>) ((List<Object>) firstTransaction(root).get('SalesTransactionItem'))[0];
    }

    private static Map<String, Object> finalizePricedJson() {
        return SIAE_POSH_PricingTTPPFlow.finalizeOutput((Map<String, Object>) JSON.deserializeUntyped(PRICED_JSON));
    }

    private static SIAE_POSH_PricingTTPPFlow.FlowOutput run(String pricingResultJson) {
        SIAE_POSH_PricingTTPPFlow.FlowInput input = new SIAE_POSH_PricingTTPPFlow.FlowInput();
        input.pricingResultJson = pricingResultJson;
        input.startDate = '2026-11-15';
        return SIAE_POSH_PricingTTPPFlow.execute(new List<SIAE_POSH_PricingTTPPFlow.FlowInput>{ input })[0];
    }

    @isTest
    static void finalizeOutputSumsLineTotalsIntoHeaderTotals() {
        Map<String, Object> salesTransaction = firstTransaction(finalizePricedJson());

        System.assertEquals(55.01, (Decimal) salesTransaction.get('TotalAmount'));
        System.assertEquals(55.01, (Decimal) salesTransaction.get('Subtotal'));
    }

    @isTest
    static void finalizeOutputTurnsPriceDetailsIntoObject() {
        Map<String, Object> root = finalizePricedJson();

        Map<String, Object> priceDetails = (Map<String, Object>) firstTransaction(root).get('SIAE_PriceDetails__c');
        System.assertEquals(1, ((List<Object>) priceDetails.get('lineItems')).size());
    }

    @isTest
    static void finalizeOutputKeepsOnlyTtppContractFields() {
        Map<String, Object> root = finalizePricedJson();

        System.assertEquals(new Set<String>{ 'SalesTransaction' }, root.keySet());
        System.assertEquals(
            new Set<String>{ 'PriceBooks', 'TotalAmount', 'Subtotal', 'SIAE_PriceDetails__c', 'SalesTransactionItem' },
            firstTransaction(root).keySet()
        );
        System.assertEquals(
            new Set<String>{
                'LineItem', 'Product', 'ItemProductCode', 'LineItemQuantity', 'NetUnitPrice', 'TotalLineAmount',
                'SIAE_TotalDA__c', 'SIAE_DirittiConnessi__c'
            },
            firstItem(root).keySet()
        );
    }

    @isTest
    static void executeReturnsErrorWhenFestePrivateAttributesAreMissing() {
        SIAE_POSH_PricingTTPPFlow.FlowOutput output = run(
            '{"SalesTransaction": [{"SalesTransactionItem": [{"LineItem": "LI1"}]}]}'
        );

        System.assertEquals('ERROR', output.status);
        System.assert(output.message.contains('Attributi TTPP mancanti per line item LI1'), output.message);
    }

    @isTest
    static void executeReturnsErrorOnBlankJson() {
        SIAE_POSH_PricingTTPPFlow.FlowOutput output = run('');

        System.assertEquals('ERROR', output.status);
        System.assertEquals('Input JSON vuoto o nullo.', output.message);
    }
}