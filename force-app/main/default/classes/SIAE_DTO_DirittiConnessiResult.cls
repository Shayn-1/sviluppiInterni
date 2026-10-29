/**
 * @description       : 
 * @author            : Domenico Del Prete - domenico.delprete@nttdata.com
 * @group             : NTT Data
 * @last modified on  : 04-23-2026
 * @last modified by  : Domenico Del Prete - domenico.delprete@nttdata.com
**/
public with sharing class SIAE_DTO_DirittiConnessiResult {
    public Decimal totaleComplessivo { get; set; }
    public List<LicenzaDetail> dettagliPerOrderItem { get; set; }

    public SIAE_DTO_DirittiConnessiResult() {
        this.totaleComplessivo = 0;
        this.dettagliPerOrderItem = new List<LicenzaDetail>();
    }

    public class LicenzaDetail {
        public String orderItemId { get; set; }
        public Decimal subtotale { get; set; }
        public Decimal subtotalePreSconto { get; set; }
        public Decimal importoVoceIncassoPrimaria { get; set; }
        public Decimal importoVoceIncassoSecondaria { get; set; }
        public List<DispositivoDetail> dettagliDispositivi { get; set; }

        public LicenzaDetail() {
            this.subtotale = 0;
            this.subtotalePreSconto = 0;
            this.importoVoceIncassoPrimaria = 0;
            this.importoVoceIncassoSecondaria = 0;
            this.dettagliDispositivi = new List<DispositivoDetail>();
        }
    }

    public class DispositivoDetail {
        public String tipoDispositivo { get; set; }

        public String revenueItem { get; set; }
        public String revenueItemType { get; set; }
        public String instrumentId { get; set; }

        public Integer unitaApplicata { get; set; }
        public Decimal importoBase { get; set; }
        public Decimal importoModifica { get; set; }
        public Decimal importoRiga { get; set; }
        public String nota { get; set; }

        public DispositivoDetail() {
            this.importoBase = 0;
            this.importoModifica = 0;
            this.importoRiga = 0;
        }
    }
}