@IsTest
private class SIAE_TR_Order_T {

    private static final String STATUS_DRAFT = 'Draft';

    @IsTest
    static void shouldSetPagataDdaWhenIncludeDcFalse() {
        resetFlags();

        Order ord = createOrderWithProduct('Test Account DDA', false);

        Test.startTest();
        ord.Status = SIAE_TR_Order_U_ManageStatus.STATUS_PAGATA;
        Database.update(ord, System.AccessLevel.SYSTEM_MODE);
        Test.stopTest();

        Order reloadedOrder = getOrder(ord.Id);

        System.assertEquals(
            SIAE_TR_Order_U_ManageStatus.STATUS_PAGATA_DDA,
            reloadedOrder.Status,
            'Se IncludeDC è false, lo status Pagata deve diventare Pagata_DDA.'
        );

        System.assertEquals(
            true,
            SIAE_TR_Order_U_ManageActions.processedOrderIds.contains(ord.Id),
            'Le action Order devono essere intercettate quando lo status finale è Pagata_DDA.'
        );
    }

    @IsTest
    static void shouldKeepPagataWhenIncludeDcTrue() {
        resetFlags();

        Order ord = createOrderWithProduct('Test Account DC', true);

        Test.startTest();
        ord.Status = SIAE_TR_Order_U_ManageStatus.STATUS_PAGATA;
        Database.update(ord, System.AccessLevel.SYSTEM_MODE);
        Test.stopTest();

        Order reloadedOrder = getOrder(ord.Id);

        System.assertEquals(
            SIAE_TR_Order_U_ManageStatus.STATUS_PAGATA,
            reloadedOrder.Status,
            'Se IncludeDC è true, lo status Pagata deve rimanere Pagata.'
        );

        System.assertEquals(
            true,
            SIAE_TR_Order_U_ManageActions.processedOrderIds.contains(ord.Id),
            'Le action Order devono essere intercettate quando lo status finale è Pagata.'
        );
    }

    @IsTest
    static void shouldDoNothingWhenStatusDoesNotChange() {
        resetFlags();

        Order ord = createOrderWithProduct('Test Account No Status Change', false);

        Test.startTest();
        ord.SIAE_IncludeDC__c = true;
        Database.update(ord, System.AccessLevel.SYSTEM_MODE);
        Test.stopTest();

        Order reloadedOrder = getOrder(ord.Id);

        System.assertEquals(
            STATUS_DRAFT,
            reloadedOrder.Status,
            'Se lo status non cambia, il trigger non deve modificare lo status.'
        );

        System.assertEquals(
            false,
            SIAE_TR_Order_U_ManageActions.processedOrderIds.contains(ord.Id),
            'Se lo status non cambia, non devono partire le action Order.'
        );
    }

    @IsTest
    static void shouldSkipTriggerWhenTriggerOffIsTrue() {
        resetFlags();

        Order ord = createOrderWithProduct('Test Account Trigger Off', false);

        try {
            SIAE_TR_Order_Handler.triggerOff = true;

            Test.startTest();
            ord.Status = SIAE_TR_Order_U_ManageStatus.STATUS_PAGATA;
            Database.update(ord, System.AccessLevel.SYSTEM_MODE);
            Test.stopTest();

            Order reloadedOrder = getOrder(ord.Id);

            System.assertEquals(
                SIAE_TR_Order_U_ManageStatus.STATUS_PAGATA,
                reloadedOrder.Status,
                'Se triggerOff è true, lo status non deve essere trasformato in Pagata_DDA.'
            );

            System.assertEquals(
                false,
                SIAE_TR_Order_U_ManageActions.processedOrderIds.contains(ord.Id),
                'Se triggerOff è true, non devono partire le action Order.'
            );

        } finally {
            SIAE_TR_Order_Handler.triggerOff = false;
        }
    }

    @IsTest
    static void shouldSkipOnlyActionsWhenActionsOffIsTrue() {
        resetFlags();

        Order ord = createOrderWithProduct('Test Account Actions Off', false);

        try {
            SIAE_TR_Order_U_ManageActions.actionsOff = true;

            Test.startTest();
            ord.Status = SIAE_TR_Order_U_ManageStatus.STATUS_PAGATA;
            Database.update(ord, System.AccessLevel.SYSTEM_MODE);
            Test.stopTest();

            Order reloadedOrder = getOrder(ord.Id);

            System.assertEquals(
                SIAE_TR_Order_U_ManageStatus.STATUS_PAGATA_DDA,
                reloadedOrder.Status,
                'Se actionsOff è true, la gestione status deve comunque funzionare.'
            );

            System.assertEquals(
                false,
                SIAE_TR_Order_U_ManageActions.processedOrderIds.contains(ord.Id),
                'Se actionsOff è true, non devono partire le action Order.'
            );

        } finally {
            SIAE_TR_Order_U_ManageActions.actionsOff = false;
        }
    }

    @IsTest
    static void shouldSupportBulkUpdate() {
        resetFlags();

        Order orderWithoutDc = createOrderWithProduct('Test Account Bulk DDA', false);
        Order orderWithDc = createOrderWithProduct('Test Account Bulk DC', true);

        orderWithoutDc.Status = SIAE_TR_Order_U_ManageStatus.STATUS_PAGATA;
        orderWithDc.Status = SIAE_TR_Order_U_ManageStatus.STATUS_PAGATA;

        Test.startTest();
        Database.update(new List<Order>{ orderWithoutDc, orderWithDc }, System.AccessLevel.SYSTEM_MODE);
        Test.stopTest();

        Map<Id, Order> reloadedOrders = new Map<Id, Order>([
            SELECT Id, Status, SIAE_IncludeDC__c
            FROM Order
            WHERE Id IN :new Set<Id>{ orderWithoutDc.Id, orderWithDc.Id }
        ]);

        System.assertEquals(
            SIAE_TR_Order_U_ManageStatus.STATUS_PAGATA_DDA,
            reloadedOrders.get(orderWithoutDc.Id).Status,
            'In bulk, l’Order senza DC deve diventare Pagata_DDA.'
        );

        System.assertEquals(
            SIAE_TR_Order_U_ManageStatus.STATUS_PAGATA,
            reloadedOrders.get(orderWithDc.Id).Status,
            'In bulk, l’Order con DC deve rimanere Pagata.'
        );

        System.assertEquals(
            true,
            SIAE_TR_Order_U_ManageActions.processedOrderIds.contains(orderWithoutDc.Id),
            'In bulk, devono essere intercettate le action per Order Pagata_DDA.'
        );

        System.assertEquals(
            true,
            SIAE_TR_Order_U_ManageActions.processedOrderIds.contains(orderWithDc.Id),
            'In bulk, devono essere intercettate le action per Order Pagata.'
        );
    }

    @IsTest
    static void shouldValidateStatusUtilityMethods() {
        Order oldOrder = new Order(Status = STATUS_DRAFT);
        Order newOrder = new Order(Status = SIAE_TR_Order_U_ManageStatus.STATUS_PAGATA);

        System.assertEquals(
            true,
            SIAE_TR_Order_U_ManageStatus.isStatusChanged(oldOrder, newOrder),
            'isStatusChanged deve tornare true se lo status cambia.'
        );

        System.assertEquals(
            true,
            SIAE_TR_Order_U_ManageStatus.isTargetPaymentStatus(SIAE_TR_Order_U_ManageStatus.STATUS_PAGATA),
            'Pagata deve essere considerato uno status target.'
        );

        System.assertEquals(
            true,
            SIAE_TR_Order_U_ManageStatus.isTargetPaymentStatus(SIAE_TR_Order_U_ManageStatus.STATUS_PAGATA_DDA),
            'Pagata_DDA deve essere considerato uno status target.'
        );

        System.assertEquals(
            false,
            SIAE_TR_Order_U_ManageStatus.isTargetPaymentStatus(STATUS_DRAFT),
            'Draft non deve essere considerato uno status target.'
        );
    }
    
    @IsTest
    static void shouldCoverOrderHandlerEmptyMethodsAndFlags() {
        resetFlags();
    
        SIAE_TR_Order_Handler handler = new SIAE_TR_Order_Handler();
    
        System.assertEquals(false, handler.skipTrigger(), 'Di default il trigger non deve essere skippato.');
        System.assertEquals(false, handler.stopRecursion(), 'Di default non deve bloccare la ricorsione.');
    
        handler.executedTrigger();
    
        handler.onBeforeInsert(new List<SObject>());
        handler.onBeforeDelete(new Map<Id, SObject>());
        handler.onAfterInsert(new Map<Id, SObject>());
        handler.onAfterDelete(new Map<Id, SObject>());
        handler.onAfterUndelete(new Map<Id, SObject>());
    }

    private static void resetFlags() {
        SIAE_TR_Order_Handler.triggerOff = false;
        SIAE_TR_Order_U_ManageActions.actionsOff = false;
        SIAE_TR_Order_U_ManageActions.processedOrderIds.clear();
    }

    private static Order createOrderWithProduct(String accountName, Boolean includeDC) {
        Id standardPricebookId = Test.getStandardPricebookId();

        Account acc = new Account(Name = accountName);
        insert acc;

        Product2 product = new Product2(
            Name = 'Test Product ' + accountName,
            IsActive = true
        );
        insert product;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = product.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert pbe;

        Order ord = new Order(
            AccountId = acc.Id,
            EffectiveDate = Date.today(),
            Status = STATUS_DRAFT,
            Pricebook2Id = standardPricebookId,
            SIAE_IncludeDC__c = includeDC
        );
        Database.insert(ord, System.AccessLevel.SYSTEM_MODE);

        OrderItem item = new OrderItem(
            OrderId = ord.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 100
        );
        insert item;

        return ord;
    }

    private static Order getOrder(Id orderId) {
        return [
            SELECT Id, Status, SIAE_IncludeDC__c
            FROM Order
            WHERE Id = :orderId
        ];
    }
}