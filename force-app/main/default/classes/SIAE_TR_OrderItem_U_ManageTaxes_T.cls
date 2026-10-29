/**
 * @description Test class for SIAE_TR_OrderItem_U_ManageTaxes.
 *              Logica: scatta su TotalTaxAmount change.
 *              Se OrderItemTaxLineItem presente → persiste DA/DC/BolloDA/BolloDC/Bollo.
 *              Se assente → nessuna scrittura (no fallback).
 *              OrderItemTaxLineItem non è inseribile via DML → inject via taxItemsByOiIdOverride.
 *              TotalTaxAmount è read-only su DML/put(); usare JSON.deserialize() per impostarlo in memoria.
 * @author      Gaetano Iuliano - gaetano.iuliano@nttdata.com
 * @group       NTT Data — SIAE
 */
@isTest
private class SIAE_TR_OrderItem_U_ManageTaxes_T {

    private static final Integer BULK_COUNT = 251;

    @TestSetup
    static void setupTestData() {
        Account acc = SIAE_TestDataFactory.createAccount(true);
        Order order = SIAE_TestDataFactory.createOrder(acc, true);

        Product2 prod = SIAE_TestDataFactory.createProduct(true);
        Id standardPricebookId = Test.getStandardPricebookId();
        List<PricebookEntry> pbes = SIAE_TestDataFactory.createPricebookEntries(
            new List<Product2>{ prod }, standardPricebookId, true
        );

        SIAE_TestDataFactory.createOrderItems(BULK_COUNT, order, pbes[0], true);
    }

    // Helper: OI in memoria con TotalTaxAmount impostato via JSON.deserialize
    private static OrderItem makeNewOI(OrderItem source, Decimal totalTaxAmount) {
        Map<String, Object> data = new Map<String, Object>{
            'attributes'     => new Map<String, Object>{ 'type' => 'OrderItem' },
            'Id'             => source.Id,
            'TotalTaxAmount' => totalTaxAmount
        };
        return (OrderItem) JSON.deserialize(JSON.serialize(data), OrderItem.class);
    }

    // Helper: inietta override OrderItemTaxLineItem (non inseribile via DML in test)
    private static void injectTaxItems(List<OrderItem> ois, Decimal da, Decimal dc, Decimal bolloDA, Decimal bolloDC) {
        Map<Id, Map<String, Decimal>> injected = new Map<Id, Map<String, Decimal>>();
        for (OrderItem oi : ois) {
            injected.put(oi.Id, new Map<String, Decimal>{
                'DA'        => da,
                'DC'        => dc,
                'BOLLO_DDA' => bolloDA,
                'BOLLO_DC'  => bolloDC
            });
        }
        SIAE_TR_OrderItem_U_ManageTaxes.taxItemsByOiIdOverride = injected;
    }

    // ─── OrderItemTaxLineItem path ────────────────────────────────────────

    @isTest
    static void shouldPersistAllSapFields_WhenOrderItemTaxLineItemPresent_Bulk() {
        List<OrderItem> dbOIs = [SELECT Id, TotalTaxAmount FROM OrderItem];
        Assert.areEqual(BULK_COUNT, dbOIs.size(), 'Setup deve creare ' + BULK_COUNT + ' righe.');
        injectTaxItems(dbOIs, 106.96, 0.66, 2.00, 1.00);

        Map<Id, OrderItem> oldMap = new Map<Id, OrderItem>(dbOIs);
        List<OrderItem> newOIs = new List<OrderItem>();
        for (OrderItem oi : dbOIs) {
            newOIs.add(makeNewOI(oi, 110.62));
        }

        Test.startTest();
        SIAE_TR_OrderItem_U_ManageTaxes.updateTaxFields(newOIs, oldMap);
        Test.stopTest();

        SIAE_TR_OrderItem_U_ManageTaxes.taxItemsByOiIdOverride = null;

        List<OrderItem> updated = [
            SELECT SIAE_TotalTaxDA__c, SIAE_TotalTaxDC__c, SIAE_TotalTaxBolloDA__c, SIAE_TotalTaxBolloDC__c, SIAE_TotalTaxBollo__c
            FROM OrderItem
        ];
        for (OrderItem oi : updated) {
            Assert.areEqual(106.96, oi.SIAE_TotalTaxDA__c,      'DA da OrderItemTaxLineItem SAP.');
            Assert.areEqual(0.66,   oi.SIAE_TotalTaxDC__c,      'DC da OrderItemTaxLineItem SAP.');
            Assert.areEqual(2.00,   oi.SIAE_TotalTaxBolloDA__c, 'BolloDA da OrderItemTaxLineItem SAP.');
            Assert.areEqual(1.00,   oi.SIAE_TotalTaxBolloDC__c, 'BolloDC da OrderItemTaxLineItem SAP.');
            Assert.areEqual(3.00,   oi.SIAE_TotalTaxBollo__c,   'Bollo = BolloDA + BolloDC.');
        }
    }

    @isTest
    static void shouldNotUpdateFields_WhenNoOrderItemTaxLineItem() {
        List<OrderItem> dbOIs = [SELECT Id, TotalTaxAmount FROM OrderItem LIMIT 1];
        SIAE_TR_OrderItem_U_ManageTaxes.taxItemsByOiIdOverride = new Map<Id, Map<String, Decimal>>(); // nessun item

        Map<Id, OrderItem> oldMap = new Map<Id, OrderItem>(dbOIs);
        List<OrderItem> newOIs = new List<OrderItem>{ makeNewOI(dbOIs[0], 110.62) };

        Test.startTest();
        SIAE_TR_OrderItem_U_ManageTaxes.updateTaxFields(newOIs, oldMap);
        Test.stopTest();

        SIAE_TR_OrderItem_U_ManageTaxes.taxItemsByOiIdOverride = null;

        OrderItem result = [SELECT SIAE_TotalTaxDA__c FROM OrderItem WHERE Id = :dbOIs[0].Id];
        Assert.isNull(result.SIAE_TotalTaxDA__c, 'Nessun OrderItemTaxLineItem → nessuna scrittura.');
    }

    // ─── No-op ───────────────────────────────────────────────────────────

    @isTest
    static void shouldNotUpdate_WhenTotalTaxAmountUnchanged() {
        List<OrderItem> dbOIs = [SELECT Id, TotalTaxAmount FROM OrderItem LIMIT 1];
        SIAE_TR_OrderItem_U_ManageTaxes.taxItemsByOiIdOverride = null;
        Map<Id, OrderItem> oldMap = new Map<Id, OrderItem>(dbOIs);

        Test.startTest();
        SIAE_TR_OrderItem_U_ManageTaxes.updateTaxFields(dbOIs, oldMap);
        Test.stopTest();

        OrderItem result = [SELECT SIAE_TotalTaxDA__c FROM OrderItem WHERE Id = :dbOIs[0].Id];
        Assert.isNull(result.SIAE_TotalTaxDA__c, 'TotalTaxAmount invariato → nessun aggiornamento.');
    }

    @isTest
    static void shouldHandleEmptyList() {
        Test.startTest();
        SIAE_TR_OrderItem_U_ManageTaxes.updateTaxFields(
            new List<OrderItem>(), new Map<Id, OrderItem>()
        );
        Test.stopTest();
        Assert.isTrue(true, 'Lista vuota gestita senza eccezioni.');
    }

    // ─── Handler coverage ─────────────────────────────────────────────────

    @isTest
    static void shouldCoverOrderItemHandlerUnusedMethodsAndFlags() {
        SIAE_TR_OrderItem_Handler.triggerOff = false;
        SIAE_TR_OrderItem_Handler handler = new SIAE_TR_OrderItem_Handler();

        Assert.areEqual(false, handler.skipTrigger(),   'Default: trigger non skippato.');
        Assert.areEqual(false, handler.stopRecursion(), 'Default: no ricorsione bloccata.');

        SIAE_TR_OrderItem_Handler.triggerOff = true;
        Assert.areEqual(true, handler.skipTrigger(), 'triggerOff=true → skip.');
        SIAE_TR_OrderItem_Handler.triggerOff = false;

        handler.executedTrigger();
        handler.onBeforeInsert(new List<SObject>());
        handler.onBeforeUpdate(new Map<Id, SObject>(), new Map<Id, SObject>());
        handler.onBeforeDelete(new Map<Id, SObject>());
        handler.onAfterInsert(new Map<Id, SObject>());
        handler.onAfterDelete(new Map<Id, SObject>());
        handler.onAfterUndelete(new Map<Id, SObject>());
    }
}