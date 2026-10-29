/**
 * @description       :
 * @author            : Domenico Del Prete - domenico.delprete@nttdata.com
 * @group             : NTT Data
 * @last modified on  : 06-30-2026
 * @last modified by  : Domenico Del Prete - domenico.delprete@nttdata.com
**/
public with sharing class SIAE_UTIL_Log {
   public static Integer maxLength = 131072;

   /**
     * Logga request + response in un unico record SIAE_Log__c (DML diretto).
     * Da chiamare a fine transazione, dopo aver ottenuto la response.
     * Non usare in catch block: se la transazione è già in rollback, questo DML si perde.
     * Non usare se nella stessa transazione è già stato fatto un DML prima del callout outbound.
     */
    public static void logRequestResponse(String correlationId, String endpoint, String httpMethod, String recordId, String requestPayload, String responsePayload, Integer statusCode, String className) {
        logRequestResponse(correlationId, endpoint, httpMethod, recordId, requestPayload, responsePayload, statusCode, className, false);
    }

    /**
     * Overload con flag usePlatformEvent.
     * Usare usePlatformEvent=true quando nella stessa transazione è presente un callout outbound
     * preceduto da DML (es. update record → Http.send()), in modo da evitare il vincolo DML-after-callout.
     * Il Flow subscriber SIAE_LogEvent_CreateLog creerà il record SIAE_Log__c in una transazione separata.
     */
    public static void logRequestResponse(String correlationId, String endpoint, String httpMethod, String recordId, String requestPayload, String responsePayload, Integer statusCode, String className, Boolean usePlatformEvent) {
        if (usePlatformEvent) {
            SIAE_PE_LogEvent__e event = new SIAE_PE_LogEvent__e();
            event.SIAE_CorrelationId__c   = correlationId;
            event.SIAE_Endpoint__c        = endpoint;
            event.SIAE_HttpMethod__c      = httpMethod;
            event.SIAE_RecordId__c        = recordId;
            event.SIAE_RequestPayload__c  = requestPayload  != null && requestPayload.length()  > maxLength ? requestPayload.substring(0, maxLength)  : requestPayload;
            event.SIAE_ResponsePayload__c = responsePayload != null && responsePayload.length() > maxLength ? responsePayload.substring(0, maxLength) : responsePayload;
            event.SIAE_StatusCode__c      = statusCode;
            event.SIAE_ClassName__c       = className;
            event.SIAE_LogType__c         = 'REQUEST_RESPONSE';
            event.SIAE_LogDateTime__c     = Datetime.now();
            EventBus.publish(event);
        } else {
            SIAE_Log__c log = new SIAE_Log__c();
            log.SIAE_CorrelationId__c   = correlationId;
            log.SIAE_Endpoint__c        = endpoint;
            log.SIAE_HttpMethod__c      = httpMethod;
            log.SIAE_RecordId__c        = recordId;
            log.SIAE_RequestPayload__c  = requestPayload  != null && requestPayload.length()  > maxLength ? requestPayload.substring(0, maxLength)  : requestPayload;
            log.SIAE_ResponsePayload__c = responsePayload != null && responsePayload.length() > maxLength ? responsePayload.substring(0, maxLength) : responsePayload;
            log.SIAE_StatusCode__c      = statusCode;
            log.SIAE_ClassName__c       = className;
            log.SIAE_LogType__c         = 'REQUEST_RESPONSE';
            log.SIAE_LogDateTime__c     = Datetime.now();
            SIAE_UTIL_DML.insertRecord(log);
            
        }
    }

    /**
     * Logga un'eccezione tramite Platform Event (PublishImmediately).
     * Il log viene persistito anche se la transazione principale fa rollback.
     * Il Flow subscriber SIAE_LogEvent_CreateLog creerà il record SIAE_Log__c.
     */
    public static void logException( Exception ex, String correlationId, String recordId, String className) {
        String excMessage = ex.getMessage() + '\n' + ex.getStackTraceString();
        logError(excMessage, correlationId, recordId, className);
    }

    /**
     * Logga un messaggio di errore (stringa) tramite Platform Event (PublishImmediately).
     * Utile quando l'errore non deriva da un'Exception, ad es. i Database.Error
     * dei record falliti in una DML partial-success (allOrNone = false).
     * Il log viene persistito anche se la transazione principale fa rollback.
     */
    public static void logError(String errorMessage, String correlationId, String recordId, String className) {
        logErrors(new List<ErrorLog>{ new ErrorLog(errorMessage, correlationId, recordId, className) });
    }

    /**
     * Logga in bulk una lista di errori con una singola EventBus.publish(List).
     * Da preferire quando si devono loggare più errori nella stessa transazione
     * (es. i record falliti di una DML partial-success), per non chiamare publish in un ciclo.
     */
    public static void logErrors(List<ErrorLog> errors) {
        if (errors == null || errors.isEmpty()) {
            return;
        }
        List<SIAE_PE_LogEvent__e> events = new List<SIAE_PE_LogEvent__e>();
        for (ErrorLog e : errors) {
            SIAE_PE_LogEvent__e event = new SIAE_PE_LogEvent__e();
            event.SIAE_CorrelationId__c = e.correlationId;
            event.SIAE_RecordId__c      = e.recordId;
            event.SIAE_ErrorMessage__c  = e.errorMessage != null ? e.errorMessage.abbreviate(32767) : '';
            event.SIAE_ClassName__c     = e.className;
            event.SIAE_LogType__c       = 'EXCEPTION';
            event.SIAE_LogDateTime__c   = Datetime.now();
            events.add(event);
        }
        EventBus.publish(events);
    }

    /**
     * DTO per il logging bulk di errori tramite logErrors.
     */
    public class ErrorLog {
        public String errorMessage;
        public String correlationId;
        public String recordId;
        public String className;

        public ErrorLog(String errorMessage, String correlationId, String recordId, String className) {
            this.errorMessage  = errorMessage;
            this.correlationId = correlationId;
            this.recordId      = recordId;
            this.className     = className;
        }
    }

    /**
     * Logga un errore proveniente da un componente LWC.
     * Annotazione @AuraEnabled per essere richiamato direttamente da JavaScript.
     * Crea un nuovo record SIAE_Log__c nella propria transazione Apex.
     */
    @AuraEnabled
    public static void logFromLwc(String errorMessage, String componentName, String recordId) {
        SIAE_Log__c log = new SIAE_Log__c();
        log.SIAE_ErrorMessage__c = errorMessage != null ? errorMessage.abbreviate(32767) : '';
        log.SIAE_ClassName__c    = componentName;
        log.SIAE_RecordId__c     = recordId;
        log.SIAE_LogType__c      = 'EXCEPTION';
        log.SIAE_LogDateTime__c  = Datetime.now();
        SIAE_UTIL_DML.insertRecords(new List<SIAE_Log__c>{ log });
    }
}