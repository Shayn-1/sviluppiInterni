/**
 * @description       : Handler invocabile da Record-Triggered Flow per sincronizzare
 *                      il campo Product2.SIAE_BusinessRule__c in base alle
 *                      ProductConfigurationRule attive.
 * @author            : Rondinella Francesco - francesco.rondinella@nttdata.com
 * @group             : NTT Data
 * @last modified on  : 04-09-2026
**/
public with sharing class SIAE_ProductConfigurationRuleHandler {

    /**
     * Wrapper di input per il Flow.
     *
     * operationType:
     * - INSERT
     * - UPDATE
     * - DELETE
     *
     * recordId:
     * - Id della ProductConfigurationRule triggerata
     *
     * configurationRuleDefinition:
     * - valore corrente del record ($Record.ConfigurationRuleDefinition)
     *
     * oldConfigurationRuleDefinition:
     * - valore precedente del record ($Record__Prior.ConfigurationRuleDefinition)
     * - da valorizzare nei casi UPDATE
     */
    public class FlowInput {
        @InvocableVariable(required=true)
        public String operationType;

        @InvocableVariable
        public Id recordId;

        @InvocableVariable
        public String configurationRuleDefinition;

        @InvocableVariable
        public String oldConfigurationRuleDefinition;
    }

    /**
     * Wrapper interno testabile.
     *
     * Serve per scollegare la logica di parsing e aggregazione
     * dalla dipendenza diretta dall'oggetto ProductConfigurationRule,
     * così da poter coprire il core della logica nei test.
     */
    @TestVisible
    private class RuleInput {
        public Id ruleId;
        public String definitionJson;

        public RuleInput() {}

        public RuleInput(Id ruleId, String definitionJson) {
            this.ruleId = ruleId;
            this.definitionJson = definitionJson;
        }
    }

    /**
     * Metodo invocabile dal Flow.
     *
     * Il Flow passa i dati del record triggerato:
     * - individua i Product2 impattati
     * - esclude la rule corrente nei casi di DELETE
     * - rigenera il JSON aggregato delle regole attive
     * - aggiorna Product2.SIAE_BusinessRule__c
     */
    @InvocableMethod(
        label='Sync Product Business Rules'
        description='Rigenera il JSON SIAE_BusinessRule__c dei Product2 impattati da ProductConfigurationRule'
    )
    public static void syncBusinessRulesFromFlow(List<FlowInput> inputs) {
        if (inputs == null || inputs.isEmpty()) return;

        Set<Id> productIdsToRebuild = new Set<Id>();
        Set<Id> ruleIdsToExclude = new Set<Id>();

        for (FlowInput input : inputs) {
            if (input == null || String.isBlank(input.operationType)) continue;

            String operationType = input.operationType.trim().toUpperCase();

            // Caso INSERT:
            // il Flow passa solo la definizione corrente,
            // quindi ricaviamo il Product2 da quella
            if (operationType == 'INSERT') {
                String productId = extractProductIdFromDefinition(input.configurationRuleDefinition);
                if (!String.isBlank(productId)) {
                    productIdsToRebuild.add((Id) productId);
                }

            // Caso UPDATE:
            // dobbiamo considerare sia il prodotto precedente
            // sia il prodotto nuovo, perché la regola potrebbe
            // essere stata spostata da un prodotto a un altro
            } else if (operationType == 'UPDATE') {
                String oldProductId = extractProductIdFromDefinition(input.oldConfigurationRuleDefinition);
                String newProductId = extractProductIdFromDefinition(input.configurationRuleDefinition);

                if (!String.isBlank(oldProductId)) {
                    productIdsToRebuild.add((Id) oldProductId);
                }
                if (!String.isBlank(newProductId)) {
                    productIdsToRebuild.add((Id) newProductId);
                }

            // Caso DELETE:
            // il record è ancora disponibile nel before-delete Flow (non è possibile farlo in after),
            // quindi ricaviamo il prodotto dalla definizione corrente.
            // Inoltre escludiamo esplicitamente la rule in cancellazione
            // dalla ricostruzione finale
            } else if (operationType == 'DELETE') {
                String productId = extractProductIdFromDefinition(input.configurationRuleDefinition);
                if (!String.isBlank(productId)) {
                    productIdsToRebuild.add((Id) productId);
                }

                if (input.recordId != null) {
                    ruleIdsToExclude.add(input.recordId);
                }
            }
        }

        if (!productIdsToRebuild.isEmpty()) {
            rebuildProductBusinessRules(productIdsToRebuild, ruleIdsToExclude);
        }
    }

    /**
     * Metodo principale di ricostruzione del JSON business rule per prodotto.
     *
     * Per ciascun prodotto impattato:
     * 1. recupera tutte le ProductConfigurationRule attive
     * 2. esclude eventuali rule in cancellazione
     * 3. seleziona solo quelle del prodotto corrente
     * 4. converte le regole in un formato intermedio testabile
     * 5. costruisce il payload dependencies per prodotto
     * 6. serializza il JSON finale
     * 7. aggiorna Product2.SIAE_BusinessRule__c
     */
    private static void rebuildProductBusinessRules(Set<Id> productIds, Set<Id> ruleIdsToExclude) {
        if (productIds == null || productIds.isEmpty()) return;

        // Recuperiamo tutte le regole attive
        List<ProductConfigurationRule> activeRules = [
            SELECT Id, Name, Status, ConfigurationRuleDefinition
            FROM ProductConfigurationRule
            WHERE Status = 'Active'
        ];

        // Lista intermedia usata per il core testabile
        List<RuleInput> ruleInputs = new List<RuleInput>();

        for (ProductConfigurationRule rule : activeRules) {
            if (ruleIdsToExclude != null && ruleIdsToExclude.contains(rule.Id)) continue;
            if (String.isBlank(rule.ConfigurationRuleDefinition)) continue;

            String productIdStr = extractProductIdFromDefinition(rule.ConfigurationRuleDefinition);
            if (String.isBlank(productIdStr)) continue;

            Id productId;
            try { productId = (Id) productIdStr; } 
            catch (Exception e) { continue; }

            // Consideriamo solo le regole dei prodotti impattati
            if (!productIds.contains(productId)) continue;

            ruleInputs.add(new RuleInput(rule.Id, rule.ConfigurationRuleDefinition));
        }

        // Costruiamo la mappa finale:
        // Product2 Id -> lista dependencies semplificate
        Map<Id, List<Map<String, Object>>> productIdToDependencies =
            buildDependenciesByProductFromInputs(ruleInputs, productIds);

        // Recuperiamo i prodotti da aggiornare
        List<Product2> productsToUpdate = [
            SELECT Id, SIAE_BusinessRule__c
            FROM Product2
            WHERE Id IN :productIds
        ];

        List<Product2> updates = new List<Product2>();

        for (Product2 prod : productsToUpdate) {
            String newJson = null;

            if (productIdToDependencies.containsKey(prod.Id) && !productIdToDependencies.get(prod.Id).isEmpty()) { newJson = buildFinalJsonForProduct(productIdToDependencies.get(prod.Id)); }

            // Aggiorniamo solo se il valore cambia davvero
            if (prod.SIAE_BusinessRule__c != newJson) {
                updates.add(new Product2(
                    Id = prod.Id,
                    SIAE_BusinessRule__c = newJson
                ));
            }
        }

        if (!updates.isEmpty()) update updates;
    }

    /**
     * Costruisce, a partire da una lista di RuleInput,
     * la mappa finale Product2 -> dependencies.
     *
     * Questo è il core testabile della logica di aggregazione:
     * - estrae gli AttributeDefinition coinvolti
     * - carica i metadata necessari
     * - semplifica ogni regola
     * - raggruppa il risultato per prodotto
     */
    @TestVisible
    private static Map<Id, List<Map<String, Object>>> buildDependenciesByProductFromInputs(
        List<RuleInput> rules,
        Set<Id> productIds
    ) {
        Map<Id, List<Map<String, Object>>> productIdToDependencies = new Map<Id, List<Map<String, Object>>>();

        if (rules == null || rules.isEmpty() || productIds == null || productIds.isEmpty()) {
            return productIdToDependencies;
        }

        // Set di tutti gli AttributeDefinition coinvolti
        Set<Id> attributeDefIds = new Set<Id>();

        for (RuleInput rule : rules) {
            if (rule == null || String.isBlank(rule.definitionJson)) continue;
            attributeDefIds.addAll(extractAttributeIdsFromDefinition(rule.definitionJson));
        }

        // Mappa Id AttributeDefinition -> record
        Map<Id, AttributeDefinition> attrDefById = new Map<Id, AttributeDefinition>();

        // Mappa Id AttributeDefinition -> Id Picklist associata
        Map<Id, Id> attrDefIdToPicklistId = new Map<Id, Id>();

        loadAttributeDefinitions(attributeDefIds, attrDefById, attrDefIdToPicklistId);

        // Mappa PicklistId + Value/Name/DisplayValue -> Code
        Map<String, String> picklistCodeByPicklistAndValue = loadPicklistValueCodes(
            new Set<Id>(attrDefIdToPicklistId.values())
        );

        for (RuleInput rule : rules) {
            if (rule == null || String.isBlank(rule.definitionJson)) continue;

            String productIdStr = extractProductIdFromDefinition(rule.definitionJson);
            if (String.isBlank(productIdStr)) continue;

            Id productId;
            try {
                productId = (Id) productIdStr;
            } catch (Exception e) { continue; }

            if (!productIds.contains(productId)) continue;

            Map<String, Object> simplifiedRule = simplifyRuleCore(
                rule.ruleId,
                rule.definitionJson,
                attrDefById,
                attrDefIdToPicklistId,
                picklistCodeByPicklistAndValue
            );

            if (simplifiedRule == null) continue;

            if (!productIdToDependencies.containsKey(productId)) {
                productIdToDependencies.put(productId, new List<Map<String, Object>>());
            }

            List<Object> dependencies = (List<Object>) simplifiedRule.get('dependencies');
            if (dependencies != null) {
                for (Object depObj : dependencies) {
                    productIdToDependencies.get(productId).add((Map<String, Object>) depObj);
                }
            }
        }

        return productIdToDependencies;
    }

    /**
     * Serializza il payload finale da salvare sul prodotto.
     *
     * Struttura finale:
     * {
     *   "dependencies": [ ... ]
     * }
     */
    @TestVisible
    private static String buildFinalJsonForProduct(List<Map<String, Object>> dependencies) {
        if (dependencies == null || dependencies.isEmpty()) return null;

        Map<String, Object> finalPayload = new Map<String, Object>();
        finalPayload.put('dependencies', dependencies);
        return JSON.serializePretty(finalPayload);
    }

    /**
     * Carica gli AttributeDefinition coinvolti nelle regole e,
     * se presente, recupera dinamicamente il campo che punta ad AttributePicklist.
     */
    private static void loadAttributeDefinitions(
        Set<Id> attributeDefIds,
        Map<Id, AttributeDefinition> attrDefById,
        Map<Id, Id> attrDefIdToPicklistId
    ) {
        if (attributeDefIds == null || attributeDefIds.isEmpty()) return;

        // Individuiamo dinamicamente il campo relationship verso AttributePicklist
        String picklistFieldApiName = discoverAttributeDefinitionPicklistFieldApiName();

        // Costruiamo dinamicamente la query
        String soql = 'SELECT Id, Name, Code, DataType';
        if (!String.isBlank(picklistFieldApiName)) {
            soql += ', ' + picklistFieldApiName;
        }
        soql += ' FROM AttributeDefinition WHERE Id IN :attributeDefIds';

        for (SObject sob : Database.query(soql)) {
            AttributeDefinition ad = (AttributeDefinition) sob;
            attrDefById.put(ad.Id, ad);

            // Se abbiamo individuato il campo picklist, estraiamo il relativo Id
            if (!String.isBlank(picklistFieldApiName)) {
                Object rawPicklistId = sob.get(picklistFieldApiName);
                if (rawPicklistId != null) {
                    try { attrDefIdToPicklistId.put(ad.Id, (Id) String.valueOf(rawPicklistId)); } 
                    catch (Exception e) {}
                }
            }
        }
    }

    /**
     * Carica tutti i valori delle picklist coinvolte.
     *
     * Restituisce una mappa:
     * PicklistId + valore -> Code
     *
     * Il valore può essere Value, Name o DisplayValue.
     */
    private static Map<String, String> loadPicklistValueCodes(Set<Id> picklistIds) {
        Map<String, String> result = new Map<String, String>();

        if (picklistIds == null || picklistIds.isEmpty()) return result;

        for (AttributePicklistValue pv : [
            SELECT Id, PicklistId, Code, Value, Name, DisplayValue
            FROM AttributePicklistValue
            WHERE PicklistId IN :picklistIds
        ]) {
            if (pv.PicklistId == null || String.isBlank(pv.Code)) continue;

            if (pv.Value != null) result.put(buildPicklistKey(pv.PicklistId, pv.Value), pv.Code);
            if (pv.Name != null) result.put(buildPicklistKey(pv.PicklistId, pv.Name), pv.Code);
            if (pv.DisplayValue != null) result.put(buildPicklistKey(pv.PicklistId, pv.DisplayValue), pv.Code);
        }

        return result;
    }

    /**
     * Individua dinamicamente il campo di AttributeDefinition che referenzia AttributePicklist.
     *
     * Questo evita di hardcodare il nome del campo, che può variare
     * in base al package / metadato presente nell'org.
     */
    @TestVisible
    private static String discoverAttributeDefinitionPicklistFieldApiName() {
        Schema.DescribeSObjectResult describeResult = AttributeDefinition.SObjectType.getDescribe();
        Map<String, Schema.SObjectField> fieldMap = describeResult.fields.getMap();

        for (String fieldApiName : fieldMap.keySet()) {
            Schema.DescribeFieldResult fd = fieldMap.get(fieldApiName).getDescribe();

            if (fd.getType() != Schema.DisplayType.REFERENCE) continue;

            for (Schema.SObjectType refType : fd.getReferenceTo()) {
                if (refType.getDescribe().getName() == 'AttributePicklist') return fieldApiName;
            }
        }

        return null;
    }

    /**
     * Estrae il Product2 Id dal ConfigurationRuleDefinition.
     *
     * Il prodotto è nel nodo:
     * criteria[0].sourceValues[0]
     */
    @TestVisible
    private static String extractProductIdFromDefinition(String definitionJson) {
        if (String.isBlank(definitionJson)) return null;

        try {
            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(definitionJson);
            List<Object> criteria = (List<Object>) root.get('criteria');

            if (criteria == null || criteria.isEmpty()) return null;

            Map<String, Object> firstCriteria = (Map<String, Object>) criteria[0];
            List<Object> sourceValues = (List<Object>) firstCriteria.get('sourceValues');

            if (sourceValues == null || sourceValues.isEmpty() || sourceValues[0] == null) return null;

            return String.valueOf(sourceValues[0]);
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * Estrae tutti gli AttributeDefinition Id presenti nel ConfigurationRuleDefinition,
     * sia dalle condizioni sia dalle azioni.
     *
     * Serve per poter poi caricare in una sola query gli attributi coinvolti.
     */
    @TestVisible
    private static Set<Id> extractAttributeIdsFromDefinition(String definitionJson) {
        Set<Id> result = new Set<Id>();

        if (String.isBlank(definitionJson)) return result;

        try {
            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(definitionJson);

            // CONDITIONS
            List<Object> criteria = (List<Object>) root.get('criteria');
            if (criteria != null) {
                for (Object criteriaObj : criteria) {
                    Map<String, Object> criteriaMap = (Map<String, Object>) criteriaObj;
                    List<Object> conditions = (List<Object>) criteriaMap.get('conditions');

                    if (conditions != null) {
                        for (Object conditionObj : conditions) {
                            Map<String, Object> conditionMap = (Map<String, Object>) conditionObj;
                            String attrId = stringValue(conditionMap.get('attributeId'));
                            if (isSalesforceId(attrId)) result.add((Id) attrId);
                        }
                    }
                }
            }

            // ACTIONS
            List<Object> actions = (List<Object>) root.get('actions');
            if (actions != null) {
                for (Object actionObj : actions) {
                    Map<String, Object> actionMap = (Map<String, Object>) actionObj;
                    List<Object> actionParameters = (List<Object>) actionMap.get('actionParameters');

                    if (actionParameters != null) {
                        for (Object paramObj : actionParameters) {
                            Map<String, Object> paramMap = (Map<String, Object>) paramObj;
                            String attrId = stringValue(paramMap.get('attributeId'));
                            if (isSalesforceId(attrId)) result.add((Id) attrId);
                        }
                    }
                }
            }
        } catch (Exception e) {
        }

        return result;
    }

    /**
     * Adattatore di compatibilità con la versione che lavora
     * direttamente su ProductConfigurationRule.
     *
     * La logica reale è centralizzata in simplifyRuleCore.
     */
    private static Map<String, Object> simplifyRule(
        ProductConfigurationRule rule,
        Map<Id, AttributeDefinition> attrDefById,
        Map<Id, Id> attrDefIdToPicklistId,
        Map<String, String> picklistCodeByPicklistAndValue
    ) {
        if (rule == null) return null;

        return simplifyRuleCore(
            rule.Id,
            rule.ConfigurationRuleDefinition,
            attrDefById,
            attrDefIdToPicklistId,
            picklistCodeByPicklistAndValue
        );
    }

    /**
     * Core condiviso della semplificazione della regola.
     *
     * Trasforma la ConfigurationRuleDefinition in una struttura più semplice
     * del tipo:
     *
     * {
     *   "dependencies": [
     *     {
     *       "ruleId": "...",
     *       "conditionLogic": "...",
     *       "conditions": [ ... ],
     *       "actions": [ ... ]
     *     }
     *   ]
     * }
     */
    @TestVisible
    private static Map<String, Object> simplifyRuleCore(
        Id ruleId,
        String definitionJson,
        Map<Id, AttributeDefinition> attrDefById,
        Map<Id, Id> attrDefIdToPicklistId,
        Map<String, String> picklistCodeByPicklistAndValue
    ) {
        if (String.isBlank(definitionJson)) return null;

        try {
            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(definitionJson);

            Map<String, Object> result = new Map<String, Object>();
            List<Object> dependencies = new List<Object>();
            Map<String, Object> dependency = new Map<String, Object>();

            dependency.put('ruleId', ruleId);
            dependency.put('conditionLogic', stringValue(root.get('criteriaExpressionType')));

            // CONDITIONS
            List<Object> simplifiedConditions = new List<Object>();
            List<Object> criteria = (List<Object>) root.get('criteria');

            if (criteria != null) {
                for (Object criteriaObj : criteria) {
                    Map<String, Object> criteriaMap = (Map<String, Object>) criteriaObj;
                    List<Object> conditions = (List<Object>) criteriaMap.get('conditions');

                    if (conditions == null) continue;

                    for (Object conditionObj : conditions) {
                        Map<String, Object> conditionMap = (Map<String, Object>) conditionObj;

                        String attrIdStr = stringValue(conditionMap.get('attributeId'));
                        Id attrId = isSalesforceId(attrIdStr) ? (Id) attrIdStr : null;
                        AttributeDefinition attrDef = attrId != null ? attrDefById.get(attrId) : null;
                        Id picklistId = attrId != null ? attrDefIdToPicklistId.get(attrId) : null;

                        Object rawValue = extractFirstValue(conditionMap.get('values'));
                        Object finalValue = translateValueUsingMetadata(
                            rawValue,
                            attrDef,
                            picklistId,
                            picklistCodeByPicklistAndValue
                        );

                        Map<String, Object> simpleCondition = new Map<String, Object>();
                        simpleCondition.put(
                            'attributeName',
                            attrDef != null && !String.isBlank(attrDef.Code) ? attrDef.Code : firstNonBlank(stringValue(conditionMap.get('attributeName')), attrIdStr)
                        );
                        simpleCondition.put('operator', stringValue(conditionMap.get('operator')));
                        simpleCondition.put('attributeValue', finalValue);

                        simplifiedConditions.add(simpleCondition);
                    }
                }
            }

            dependency.put('conditions', simplifiedConditions);

            // ACTIONS
            List<Object> simplifiedActions = new List<Object>();
            List<Object> actions = (List<Object>) root.get('actions');

            if (actions != null) {
                for (Object actionObj : actions) {
                    Map<String, Object> actionMap = (Map<String, Object>) actionObj;
                    String actionType = stringValue(actionMap.get('actionType'));
                    String messageType = stringValue(actionMap.get('messageType'));
                    String message = stringValue(actionMap.get('message'));

                    List<Object> actionParameters = (List<Object>) actionMap.get('actionParameters');

                    // Caso action senza target attributo (es. Validate)
                    if (actionParameters == null || actionParameters.isEmpty()) {
                        Map<String, Object> simpleAction = new Map<String, Object>();
                        simpleAction.put('actionType', actionType);
                        simpleAction.put('attributeName', null);
                        simpleAction.put('attributeValue', null);
                        simpleAction.put('messageType', messageType);
                        simpleAction.put('message', message);
                        simplifiedActions.add(simpleAction);
                        continue;
                    }

                    // Caso action con uno o più target attributo
                    for (Object paramObj : actionParameters) {
                        Map<String, Object> paramMap = (Map<String, Object>) paramObj;

                        String attrIdStr = stringValue(paramMap.get('attributeId'));
                        Id attrId = isSalesforceId(attrIdStr) ? (Id) attrIdStr : null;
                        AttributeDefinition attrDef = attrId != null ? attrDefById.get(attrId) : null;
                        Id picklistId = attrId != null ? attrDefIdToPicklistId.get(attrId) : null;

                        String attributeName = attrDef != null && !String.isBlank(attrDef.Code) ? attrDef.Code : firstNonBlank(stringValue(paramMap.get('attributeName')), attrIdStr);

                        Object attributeValue = null;

                        if (actionType == 'SetAttribute' ||
                            actionType == 'SetDefaultAttributeValue' ||
                            actionType == 'SetQuantity' ||
                            actionType == 'HideAttributeValue' ||
                            actionType == 'DisableAttributeValue') {

                            Object rawValue = extractFirstValue(paramMap.get('values'));
                            attributeValue = translateValueUsingMetadata(
                                rawValue,
                                attrDef,
                                picklistId,
                                picklistCodeByPicklistAndValue
                            );
                        }

                        Map<String, Object> simpleAction = new Map<String, Object>();
                        simpleAction.put('actionType', actionType);
                        simpleAction.put('attributeName', attributeName);
                        simpleAction.put('attributeValue', attributeValue);
                        simpleAction.put('messageType', messageType);
                        simpleAction.put('message', message);

                        simplifiedActions.add(simpleAction);
                    }
                }
            }

            dependency.put('actions', simplifiedActions);

            dependencies.add(dependency);
            result.put('dependencies', dependencies);

            return result;
        } catch (Exception e) { return null; }
    }

    /**
     * Traduce il valore grezzo della regola in un valore più adatto per il frontend.
     *
     * Regole:
     * - picklist -> prova a tradurre Value/Name/DisplayValue nel relativo Code
     * - number/currency/percent -> converte in Decimal
     * - boolean -> converte in Boolean
     * - altrimenti restituisce la stringa originale
     */
    @TestVisible
    private static Object translateValueUsingMetadata(
        Object rawValue,
        AttributeDefinition attrDef,
        Id picklistId,
        Map<String, String> picklistCodeByPicklistAndValue
    ) {
        if (rawValue == null) return null;

        String rawString = String.valueOf(rawValue);

        if (attrDef != null && !String.isBlank(attrDef.DataType)) {
            String dt = attrDef.DataType.toLowerCase();

            // Se è picklist, proviamo a tradurre il valore nel relativo Code
            if (dt == 'picklist' && picklistId != null) {
                String code = picklistCodeByPicklistAndValue.get(buildPicklistKey(picklistId, rawString));
                return String.isBlank(code) ? rawString : code;
            }

            try {
                if (dt == 'number' || dt == 'currency' || dt == 'percent') return Decimal.valueOf(rawString);
                if (dt == 'boolean') return rawString == 'true';
            } catch (Exception e) { return rawString; }
        }

        return rawString;
    }

    /**
     * Se l'oggetto è una lista, restituisce il primo valore.
     * Altrimenti restituisce direttamente l'oggetto passato.
     */
    @TestVisible
    private static Object extractFirstValue(Object valuesObj) {
        if (valuesObj == null) return null;

        if (valuesObj instanceof List<Object>) {
            List<Object> values = (List<Object>) valuesObj;
            return values.isEmpty() ? null : values[0];
        }

        return valuesObj;
    }

    /**
     * Costruisce la chiave usata per mappare:
     * PicklistId + valore -> Code
     */
    @TestVisible
    private static String buildPicklistKey(Id picklistId, String value) {
        return String.valueOf(picklistId) + '###' + String.valueOf(value);
    }

    /**
     * Verifica semplice per capire se una stringa può essere un Salesforce Id.
     */
    @TestVisible
    private static Boolean isSalesforceId(String value) {
        return !String.isBlank(value) && (value.length() == 15 || value.length() == 18);
    }

    /**
     * Utility: converte un Object in String.
     */
    @TestVisible
    private static String stringValue(Object obj) {
        return obj == null ? null : String.valueOf(obj);
    }

    /**
     * Restituisce il primo valore non blank tra due stringhe.
     *
     * Serve come fallback:
     * - prima Code/Name
     * - poi Id
     */
    @TestVisible
    private static String firstNonBlank(String firstValue, String secondValue) {
        return !String.isBlank(firstValue) ? firstValue : secondValue;
    }
}