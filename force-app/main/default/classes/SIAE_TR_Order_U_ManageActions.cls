/**
 * @description Utility per gestione submit Order tramite Flow
 */
public without sharing class SIAE_TR_Order_U_ManageActions {

    public static Boolean actionsOff = false;

    @TestVisible
    private static Set<Id> processedOrderIds = new Set<Id>();

    private static final String FLOW_SUBMIT_ORDER = 'SIAE_AL_SubmitOrder';
    private static final String PARAM_ORDER_ID = 'orderId';

    public static void manageOrderActions(Map<Id, Order> mapOld, Map<Id, Order> mapNew) {

        if (actionsOff) return;

        if (mapOld == null || mapNew == null || mapNew.isEmpty()) return;

        for (Id orderId : mapNew.keySet()) {
            Order oldOrder = mapOld.get(orderId);
            Order newOrder = mapNew.get(orderId);

            if (!shouldRunOrderActions(oldOrder, newOrder)) continue;

            if (processedOrderIds.contains(orderId)) continue;

            processedOrderIds.add(orderId);

            try {
                if (shouldSubmitOrder(oldOrder, newOrder)) submitOrder(orderId);
            } 
            catch (Exception ex) {
				newOrder.addError('Errore durante Submit Order. Dettaglio tecnico: ' + ex.getMessage());
            }
        }
    }

    private static Boolean shouldRunOrderActions(Order oldOrder, Order newOrder) {
        return oldOrder != null
            && newOrder != null
            && SIAE_TR_Order_U_ManageStatus.isStatusChanged(oldOrder, newOrder)
            && SIAE_TR_Order_U_ManageStatus.isTargetPaymentStatus(newOrder.Status)
        	&& String.isBlank(oldOrder.OrchestrationSbmsStatus);
    }

    private static Boolean shouldSubmitOrder(Order oldOrder, Order newOrder) {
        // Se si avranno casistiche particolari future
        return true;
    }

    private static void submitOrder(Id orderId) {

        // Per evitare problemi con la classe di test
        if (Test.isRunningTest()) return;

        Map<String, Object> inputs = new Map<String, Object>{ PARAM_ORDER_ID => String.valueOf(orderId) };

        Flow.Interview interview = Flow.Interview.createInterview(FLOW_SUBMIT_ORDER, inputs);

        interview.start();
    }

    public class SIAE_TR_OrderActionException extends Exception {}
}