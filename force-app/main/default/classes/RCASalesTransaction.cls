public class RCASalesTransaction {
    public List<TransactionNode> transactions = new List<TransactionNode>();
    public List<ItemNode> items = new List<ItemNode>();

    public class TransactionNode {
        public List<Object> dataPath;
        public String transactionKey;
        public Map<String, Object> attributeToUpdate = new Map<String, Object>();
    }

    public class ItemNode {
        public List<Object> dataPath;
        public String transactionKey;
        public String lineItemId;
        public String productId;
        public Decimal totalDA;
        public Decimal dirittiConnessi;
        public Decimal totalTaxDA;
        public Decimal totalTaxDC;
        public Decimal netTotalPrice;
        public Datetime derivedStartDateTime;
        // Generic SalesTransactionItem fields also used by MdA.
        public String commercialCode;
        public String typeOfFlatRate;
        public String typeCoverage;
        public Decimal flatAudioAmount;
        public Decimal flatVideoAmount;
        public Decimal periodicityCoefficient;
        public Decimal coeffMaggiorazioneMQ;
        public Decimal coeffAreeEsterne;
        // Raw item tags used by the MdA pre-hook.
        public String lineItemPath;
        public String dmlStatus;
        public Object effectiveFrom;
        public String productSellingModel;

        // Runtime pricing state shared with pricing engines; not serialized by the RCA writer.
        public Decimal discountDc = 0;
        public Decimal commercialAgreementQuota = 0;
        public List<AttributeNode> attributes = new List<AttributeNode>();
        public PricingPaymentItem.Wrapper paymentWrapper = new PricingPaymentItem.Wrapper();

        public Map<String, String> attributeValueByCode = new Map<String, String>();
        public Map<String, Object> attributeToUpdate = new Map<String, Object>();

        // Extension points owned by the adopter. Kept generic so RCA core does not depend on TTPP DTOs.
        public Object pricingDetail;
        public Object frontendDetail;
    }

    public class AttributeNode {
        public List<Object> dataPath;
        public String parentLineItemId;
        public String attributeCode;
        public String attributeValue;
        public Boolean resolvedFromPicklist = false;
        public Object devicePrice;
        public Object deviceTotalPrice;
        public Map<String, Object> attributeToUpdate = new Map<String, Object>();
    }
}