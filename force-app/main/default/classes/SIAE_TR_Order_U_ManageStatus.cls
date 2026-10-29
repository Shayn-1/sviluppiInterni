/**
 * @description Utility per gestione status Order
 */
public without sharing class SIAE_TR_Order_U_ManageStatus {

    public static final String STATUS_PAGATA = 'Pagata';
    public static final String STATUS_PAGATA_DDA = 'Pagata_DDA';

    public static void managePagataDdaStatus(Map<Id, Order> mapOld, Map<Id, Order> mapNew) {

        if (mapOld == null || mapNew == null || mapNew.isEmpty()) return;

        for (Id orderId : mapNew.keySet()) {
            Order oldOrder = mapOld.get(orderId);
            Order newOrder = mapNew.get(orderId);

            if (oldOrder == null || newOrder == null) continue;

            if (!isStatusChanged(oldOrder, newOrder)) continue;

            if (newOrder.Status != STATUS_PAGATA) continue;

            Boolean includeDC = newOrder.SIAE_IncludeDC__c == true;

            if (!includeDC) newOrder.Status = STATUS_PAGATA_DDA;
        }
    }

    public static Boolean isTargetPaymentStatus(String status) {
        return status == STATUS_PAGATA || status == STATUS_PAGATA_DDA;
    }

    public static Boolean isStatusChanged(Order oldOrder, Order newOrder) {
        return oldOrder.Status != newOrder.Status;
    }
}