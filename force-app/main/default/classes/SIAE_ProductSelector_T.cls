@IsTest
private class SIAE_ProductSelector_T {

    @IsTest
    static void testByCodeReturnsMatchingProduct() {
        Product2 prod = new Product2(Name = 'Prodotto Test', ProductCode = 'PROD-001', IsActive = true);
        insert prod;

        Test.startTest();
        Product2 result = SIAE_ProductSelector.byCode('PROD-001');
        Test.stopTest();

        System.assertEquals(prod.Id, result.Id);
        System.assertEquals('PROD-001', result.ProductCode);
    }

    @IsTest
    static void testByCodeThrowsWhenProductCodeNotFound() {
        Test.startTest();
        try {
            SIAE_ProductSelector.byCode('CODICE-INESISTENTE');
            System.assert(false, 'Expected an exception for an unmatched ProductCode');
        } catch (QueryException e) {
            System.assert(true);
        }
        Test.stopTest();
    }
}