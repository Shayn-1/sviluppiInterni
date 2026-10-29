/**
 * @description      Provider DRO che invoca l'API Mulesoft `POST /api/digital/crea-locale`
 *                   per creare un Locale e i relativi Spazi a partire da un Order Salesforce.
 *                   Risolve Codice Genere e parametri dinamici tramite
 *                   SIAE_UTIL_GenereLocaleConfig (CMT SIAE_GenereLocale__mdt + SIAE_GenereLocaleParameter__mdt)
 * @author           Gaetano Iuliano - gaetano.iuliano@nttdata.com
 * @group            NTT Data — SIAE
 * @createdDate      2026-05-30
 * @lastModifiedDate 2026-07-31
 * @lastModifiedBy   Gaetano Iuliano
 */
global with sharing class SIAE_REST_CreateLocale
        implements industriesintegrationfwk.ProcessIntegrationProviderAdvanced {

    private static final String CONFIG_NAME = 'CreateLocale';

    /**
     * Denominazione degli spazi: il flusso Preventivatore non ha un campo per il nome
     * dello spazio, quindi si compone «Spazio <nome genere>» (es. "Spazio Bar"),
     * allineamento AS-IS del campo "Ambiente" in Area Privata.
     */
    private static final String SPACE_NAME_PREFIX = 'Spazio';

    public class ParametroDTO {
        public String nome;
        public String valore;
        public ParametroDTO(String n, String v) {
            this.nome   = n;
            this.valore = v;
        }
    }

    public class SpazioDataDTO {
        public String             denominazione;
        public String             idTipoSpazio;
        public String             idGenere;
        public String             idRiferimento;
        public List<ParametroDTO> parametri;
        public String             note;
    }

    public class LocaleDataDTO {
        public String             denominazione;
        public String             idGenere;
        public String             seprag;
        public Long               idEgonCiv;
        public String             dataCreazione;
        public String             note;
        public List<ParametroDTO> parametri;
        public List<SpazioDataDTO> spazi;
    }

    public class CreateLocaleRequestDTO {
        public LocaleDataDTO locale;
    }

    public class SpazioResponseDTO {
        public Long   idSpazio;
        public String denominazione;
        public String idGenere;
        public String idRiferimento;
    }

    public class CreateLocaleResponseDTO {
        public Long                    idLocale;
        public String                  denominazione;
        public String                  idGenere;
        public String                  dataCreazione;
        public List<SpazioResponseDTO> spazi;
    }

    global static List<industriesintegrationfwk.ApexProviderAttr> getProviderAttributes() {
        return SIAE_UTIL_IntegrationConfig.buildProviderAttributes(CONFIG_NAME);
    }


    global static industriesintegrationfwk.IntegrationCalloutResponse executeCallout(
        String requestGuid,
        String inputRecordId,
        String payload,
        Map<String, Object> attributes,
        industriesintegrationfwk.HttpBaseProvider httpProvider
    ) {
        Id orderId;
        String correlationId;
        industriesintegrationfwk.IntegrationCalloutResponse calloutResponse;
        try {
            if (String.isBlank(inputRecordId)) {
                throw new IllegalArgumentException('inputRecordId is required.');
            }
            Id orderItemId = (Id) inputRecordId;
            if (orderItemId.getSObjectType() != OrderItem.SObjectType) {
                throw new IllegalArgumentException('inputRecordId must be an OrderItem ID.');
            }

            orderId = [SELECT OrderId FROM OrderItem WHERE Id = :orderItemId LIMIT 1].OrderId;

            Order ord = [
                SELECT Id,
                       SIAE_LocalName__c,
                       SIAE_IdEgonCiv__c,
                       SIAE_Seprag__c,
                       (SELECT Id,
                               Product2Id,
                               Product2.ProductCode,
                               SIAE_GenereName__c
                        FROM OrderItems
                        ORDER BY CreatedDate ASC, Id ASC)
                FROM Order
                WHERE Id = :orderId
                LIMIT 1
            ];

            Set<Id> orderItemIds = new Set<Id>();
            if (ord.OrderItems != null) {
                for (OrderItem oi : ord.OrderItems) {
                    orderItemIds.add(oi.Id);
                }
            }
            Map<Id, List<OrderItemAttribute>> attrsByItem = new Map<Id, List<OrderItemAttribute>>();
            if (!orderItemIds.isEmpty()) {
                for (OrderItemAttribute a : [
                    SELECT OrderItemId, AttributeDefinition.Code, AttributeValue
                    FROM OrderItemAttribute
                    WHERE OrderItemId IN :orderItemIds
                ]) {
                    List<OrderItemAttribute> attrs = attrsByItem.get(a.OrderItemId);
                    if (attrs == null) {
                        attrs = new List<OrderItemAttribute>();
                        attrsByItem.put(a.OrderItemId, attrs);
                    }
                    attrs.add(a);
                }
            }

            if (String.isBlank(ord.SIAE_LocalName__c)) {
                throw new IllegalArgumentException('Order.SIAE_LocalName__c is required.');
            }
            if (String.isBlank(ord.SIAE_IdEgonCiv__c)) {
                throw new IllegalArgumentException('Order.SIAE_IdEgonCiv__c is required.');
            }
            if (String.isBlank(ord.SIAE_Seprag__c)) {
                throw new IllegalArgumentException('Order.SIAE_Seprag__c is required.');
            }
            if (ord.OrderItems == null || ord.OrderItems.isEmpty()) {
                throw new IllegalArgumentException('Order has no OrderItems — at least 1 spazio required.');
            }

            String configName = SIAE_UTIL_IntegrationConfig.resolveConfigName(attributes, CONFIG_NAME);

            CreateLocaleRequestDTO requestDTO = buildRequest(ord, attrsByItem);

            correlationId = UUID.randomUUID().toString();
            HttpRequest req = SIAE_UTIL_IntegrationConfig.buildHttpRequest(
                configName, String.valueOf(orderId), correlationId, JSON.serialize(requestDTO, true)
            );
            System.debug(LoggingLevel.DEBUG, '### CreateLocale REQUEST BODY ###\n' + JSON.serializePretty(requestDTO));
			System.debug('### CreateLocale REQUEST###\n' + req.getHeader('x-api-key'));
            HttpResponse res = new Http().send(req);

            Integer statusCode   = res.getStatusCode();
            String  responseBody = res.getBody();

            if (statusCode == 200) {
                CreateLocaleResponseDTO responseDTO =
                    (CreateLocaleResponseDTO) JSON.deserialize(responseBody, CreateLocaleResponseDTO.class);

                if (responseDTO.idLocale != null) {
                    update new Order(
                        Id             = orderId,
                        SIAE_LocaleId__c = String.valueOf(responseDTO.idLocale)
                    );
                }

                if (responseDTO.spazi != null && !responseDTO.spazi.isEmpty()) {
                    Map<String, Long> idRifToIdSpazio = new Map<String, Long>();
                    for (SpazioResponseDTO spazioResp : responseDTO.spazi) {
                        if (spazioResp.idRiferimento != null && spazioResp.idSpazio != null) {
                            idRifToIdSpazio.put(spazioResp.idRiferimento, spazioResp.idSpazio);
                        }
                    }
                    List<OrderItem> itemsToUpdate = new List<OrderItem>();
                    for (OrderItem oi : ord.OrderItems) {
                        Long idSpazio = idRifToIdSpazio.get(oi.Id);
                        if (idSpazio != null) {
                            itemsToUpdate.add(new OrderItem(
                                Id              = oi.Id,
                                SIAE_SpaceId__c = String.valueOf(idSpazio)
                            ));
                        }
                    }
                    if (!itemsToUpdate.isEmpty()) {
                        update itemsToUpdate;
                    }
                }

                calloutResponse = SIAE_UTIL_IntegrationConfig.buildCalloutResponse(true, statusCode, null);
                SIAE_UTIL_Log.logRequestResponse(correlationId, SIAE_UTIL_IntegrationConfig.getCalloutEndpoint(configName), 'POST', orderId,  JSON.serialize(requestDTO, true), JSON.serialize(responseBody, true), statusCode, 'SIAE_REST_CreateLocale');
                return calloutResponse;

            } else {
                String errorMsg = SIAE_UTIL_IntegrationConfig.parseErrorMessage(statusCode, responseBody);
                calloutResponse = SIAE_UTIL_IntegrationConfig.buildCalloutResponse(false, statusCode, errorMsg);
                SIAE_UTIL_Log.logRequestResponse(correlationId, SIAE_UTIL_IntegrationConfig.getCalloutEndpoint(configName), 'POST', orderId, JSON.serialize(requestDTO, true), JSON.serialize(responseBody, true), statusCode, 'SIAE_REST_CreateLocale');
                return calloutResponse;
            }

        } catch (Exception ex) {
            calloutResponse = SIAE_UTIL_IntegrationConfig.buildCalloutResponse(false, 500, ex.getMessage());
            SIAE_UTIL_Log.logException(ex, correlationId, orderId, 'SIAE_REST_CreateLocale');
            return calloutResponse;
        }
    }


    public static String buildRequestBody(Id orderId) {
        Order ord = [
            SELECT Id,
                   SIAE_LocalName__c,
                   SIAE_IdEgonCiv__c,
                   SIAE_Seprag__c,
                   (SELECT Id,
                           Product2Id,
                           Product2.ProductCode,
                           SIAE_GenereName__c
                    FROM OrderItems
                    ORDER BY CreatedDate ASC, Id ASC)
            FROM Order
            WHERE Id = :orderId
            LIMIT 1
        ];

        Set<Id> orderItemIds = new Set<Id>();
        for (OrderItem oi : ord.OrderItems) { orderItemIds.add(oi.Id); }

        Map<Id, List<OrderItemAttribute>> attrsByItem = new Map<Id, List<OrderItemAttribute>>();
        for (OrderItemAttribute a : [
            SELECT OrderItemId, AttributeDefinition.Code, AttributeValue
            FROM OrderItemAttribute
            WHERE OrderItemId IN :orderItemIds
        ]) {
            List<OrderItemAttribute> attrs = attrsByItem.get(a.OrderItemId);
            if (attrs == null) { attrs = new List<OrderItemAttribute>(); attrsByItem.put(a.OrderItemId, attrs); }
            attrs.add(a);
        }

        if (String.isBlank(ord.SIAE_LocalName__c)) {
            throw new IllegalArgumentException('Order.SIAE_LocalName__c is required.');
        }
        if (String.isBlank(ord.SIAE_IdEgonCiv__c)) {
            throw new IllegalArgumentException('Order.SIAE_IdEgonCiv__c is required.');
        }
        if (String.isBlank(ord.SIAE_Seprag__c)) {
            throw new IllegalArgumentException('Order.SIAE_Seprag__c is required.');
        }
        if (ord.OrderItems == null || ord.OrderItems.isEmpty()) {
            throw new IllegalArgumentException('Order has no OrderItems — at least 1 spazio required.');
        }

        return JSON.serializePretty(buildRequest(ord, attrsByItem));
    }

    /**
     * «Spazio <nome genere>» (es. "Spazio Bar"). Se il nome genere non è valorizzato
     * si invia il solo prefisso.
     */
    @TestVisible
    private static String buildSpaceName(String genereName) {
        return String.isNotBlank(genereName)
            ? SPACE_NAME_PREFIX + ' ' + genereName.trim()
            : SPACE_NAME_PREFIX;
    }

    @TestVisible
    private static CreateLocaleRequestDTO buildRequest(
        Order ord,
        Map<Id, List<OrderItemAttribute>> attrsByItem
    ) {
        LocaleDataDTO localeDTO  = new LocaleDataDTO();
        localeDTO.denominazione  = ord.SIAE_LocalName__c;
        localeDTO.seprag         = ord.SIAE_Seprag__c;
        localeDTO.idEgonCiv      = Long.valueOf(ord.SIAE_IdEgonCiv__c.trim());
        localeDTO.dataCreazione  = Datetime.now().format('dd/MM/yyyy HH:mm:ss');
        localeDTO.note           = null;
        localeDTO.spazi          = new List<SpazioDataDTO>();

        Map<String, ParametroDTO> localeParamsByNome = new Map<String, ParametroDTO>();

        for (OrderItem oi : ord.OrderItems) {
            SIAE_UTIL_GenereLocaleConfig.GenereConfig oiCfg =
                SIAE_UTIL_GenereLocaleConfig.load(
                    oi.SIAE_GenereName__c,
                    oi.Product2 != null ? oi.Product2.ProductCode : null
                );

            if (localeDTO.idGenere == null) {
                localeDTO.idGenere = oiCfg.codiceGenere;
            }

            for (ParametroDTO p : buildParametri(attrsByItem.get(oi.Id), oiCfg.localeParams)) {
                mergeLocaleParam(localeParamsByNome, p);
            }

            SpazioDataDTO spazioDTO  = new SpazioDataDTO();
            spazioDTO.denominazione  = buildSpaceName(oi.SIAE_GenereName__c);
            spazioDTO.idTipoSpazio   = 'GE';
            spazioDTO.idRiferimento  = oi.Id;
            spazioDTO.note           = null;
            spazioDTO.idGenere       = oiCfg.codiceGenere;
            spazioDTO.parametri      = buildParametri(attrsByItem.get(oi.Id), oiCfg.spazioParams);
            localeDTO.spazi.add(spazioDTO);
        }

        localeDTO.parametri = localeParamsByNome.values();

        CreateLocaleRequestDTO requestDTO = new CreateLocaleRequestDTO();
        requestDTO.locale = localeDTO;
        return requestDTO;
    }


    private static void mergeLocaleParam(Map<String, ParametroDTO> acc, ParametroDTO p) {
        ParametroDTO existing = acc.get(p.nome);
        if (existing == null) {
            acc.put(p.nome, p);
            return;
        }
        Decimal existingNum = SIAE_UTIL_IntegrationConfig.parseDecimalOrNull(existing.valore);
        Decimal newNum      = SIAE_UTIL_IntegrationConfig.parseDecimalOrNull(p.valore);
        if (existingNum != null && newNum != null && newNum > existingNum) {
            acc.put(p.nome, p);
        }
    }


    @TestVisible
    private static List<ParametroDTO> buildParametri(
        List<OrderItemAttribute> orderItemAttributes,
        List<SIAE_GenereLocaleParameter__mdt> mappings
    ) {
        List<ParametroDTO> result = new List<ParametroDTO>();
        if (mappings == null || mappings.isEmpty()) {
            return result;
        }

        Map<String, String> codeToValue = new Map<String, String>();
        if (orderItemAttributes != null) {
            for (OrderItemAttribute a : orderItemAttributes) {
                if (a.AttributeDefinition != null
                    && String.isNotBlank(a.AttributeDefinition.Code)
                    && String.isNotBlank(a.AttributeValue)) {
                    codeToValue.put(a.AttributeDefinition.Code, a.AttributeValue);
                }
            }
        }

        for (SIAE_GenereLocaleParameter__mdt m : mappings) {
            // Caso speciale Nave: 'utilizzo' deriva da DUE attributi (tipo nave + passeggeri).
            if (SIAE_UTIL_GenereLocaleConfig.PARAM_UTILIZZO_NAVE.equalsIgnoreCase(m.SIAE_ParameterName__c)) {
                String tipoNave   = codeToValue.get(SIAE_UTIL_GenereLocaleConfig.ATTR_TIPO_NAVE);
                String passeggeri = codeToValue.get(SIAE_UTIL_GenereLocaleConfig.ATTR_PASSEGGERI);
                if (String.isNotBlank(tipoNave) && String.isNotBlank(passeggeri)) {
                    result.add(new ParametroDTO(
                        m.SIAE_ParameterName__c,
                        SIAE_UTIL_GenereLocaleConfig.resolveUtilizzoNave(tipoNave, passeggeri)
                    ));
                } else if (m.SIAE_IsRequired__c == true) {
                    throw new IllegalArgumentException(
                        'Parametro obbligatorio mancante: ' + m.SIAE_ParameterName__c
                        + ' (richiede ' + SIAE_UTIL_GenereLocaleConfig.ATTR_TIPO_NAVE
                        + ' + ' + SIAE_UTIL_GenereLocaleConfig.ATTR_PASSEGGERI + ')'
                    );
                }
                continue;
            }

            // Parametro metadata-only senza attributo: usa SIAE_DefaultValue__c (es. capienza = 0 fisso).
            if (String.isBlank(m.SIAE_AttributeDefinitionCode__c)) {
                if (String.isNotBlank(m.SIAE_DefaultValue__c)) {
                    result.add(new ParametroDTO(m.SIAE_ParameterName__c, m.SIAE_DefaultValue__c));
                } else if (m.SIAE_IsRequired__c == true) {
                    throw new IllegalArgumentException(
                        'Parametro obbligatorio mancante: ' + m.SIAE_ParameterName__c
                        + ' (nessun AttributeDefinition.Code e nessun SIAE_DefaultValue__c configurato)'
                    );
                }
                continue;
            }
            String raw = codeToValue.get(m.SIAE_AttributeDefinitionCode__c);
            if (String.isBlank(raw)) {
                // Valore runtime assente: fallback al default se configurato.
                if (String.isNotBlank(m.SIAE_DefaultValue__c)) {
                    result.add(new ParametroDTO(m.SIAE_ParameterName__c, m.SIAE_DefaultValue__c));
                    continue;
                }
                if (m.SIAE_IsRequired__c == true) {
                    throw new IllegalArgumentException(
                        'Parametro obbligatorio mancante: ' + m.SIAE_ParameterName__c
                        + ' (atteso da AttributeDefinition.Code=' + m.SIAE_AttributeDefinitionCode__c + ')'
                    );
                }
                continue;
            }
            String validated = SIAE_UTIL_GenereLocaleConfig.resolveOutboundValue(m, raw);
            result.add(new ParametroDTO(m.SIAE_ParameterName__c, validated));
        }
        return result;
    }
}