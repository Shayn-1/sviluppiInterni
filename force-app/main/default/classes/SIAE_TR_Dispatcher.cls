/**
 * @description SIAE_TR_Dispatcher - Dispatcher for generic Trigger
 */
public without sharing class SIAE_TR_Dispatcher {

    public static void init(SIAE_TR_I_Trigger_Handler handler, System.TriggerOperation triggerEvent) {

        if (handler == null) return;

        if (handler.stopRecursion() || handler.skipTrigger()) return;

        switch on triggerEvent {
            
            when BEFORE_INSERT { handler.onBeforeInsert(Trigger.new); }
            
            when BEFORE_UPDATE { handler.onBeforeUpdate(Trigger.oldMap, Trigger.newMap);  }
            
            when BEFORE_DELETE { handler.onBeforeDelete(Trigger.oldMap);  }
            
            when AFTER_INSERT { handler.onAfterInsert(Trigger.newMap); }
            
            when AFTER_UPDATE { handler.onAfterUpdate(Trigger.oldMap, Trigger.newMap); }
            
            when AFTER_DELETE { handler.onAfterDelete(Trigger.oldMap); }
            
            when AFTER_UNDELETE { handler.onAfterUndelete(Trigger.newMap); }
            
        }

        handler.executedTrigger();
    }
}