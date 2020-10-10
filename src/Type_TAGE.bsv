package Type_TAGE;


import Vector :: *;
import FShow :: *;

export Type_TAGE :: *;
`include "parameter.bsv"

typedef Bit#(`PC_LEN)                               ProgramCounter;                           //64bits
typedef Bit#(TAdd#(`GHR4,1))                        GlobalHistory;                          //131bits
typedef Bit#(TLog#(TAdd#(`NUMTAGTABLES,1)))         TableNo;                      // 000, 001, 010, 011, 100
typedef Bit#(TLog#(`BIMODALSIZE))                   BimodalIndex;                 //8bits
typedef Bit#(TLog#(`TABLESIZE))                     TagTableIndex;                        //7bits
typedef Bit#(`BIMODAL_CTR_LEN)                      BimodalCtr;                  //2bits counter
typedef Bit#(`TAGTABLE_CTR_LEN)                     TagTableCtr;                          //3bits counter
typedef Bit#(`TAG1_SIZE)                            TableTag1;                         //8bits
typedef Bit#(`TAG2_SIZE)                            TableTag2;                         //9bits
typedef Bit#(`U_LEN)                                UsefulCtr;                   //2bits
typedef Bit#(`OUTCOME)                              ActualOutcome;               //1bit
typedef Bit#(`PRED)                                 Prediction;                         //1bit
typedef Bit#(`PRED)                                 AltPrediction;                      //1bit
typedef Bit#(`PRED)                                 Misprediction;                      //misprediction bit
typedef Bit#(`GEOM_LEN)                             GeomLength;                    //geomlength of each table
typedef Bit#(`TARGET_LEN)                           TargetLength;                 //targetlength
typedef Bit#(`PHR_LEN)                              PathHistory;

typedef union tagged {
    TableTag1 Tag1;
    TableTag2 Tag2;
} Tag deriving(Bits, Eq, FShow);

typedef struct {
    TagTableCtr ctr;
    UsefulCtr uCtr;
    Tag tag; 
} TagEntry deriving(Bits, Eq, FShow);


typedef struct {
    BimodalCtr ctr;
} BimodalEntry deriving(Bits, Eq, FShow);



typedef struct {
    BimodalIndex                                  bimodal_index;
    Vector#(`NUMTAGTABLES, TagTableIndex)         tagTable_index;
    Vector#(`NUMTAGTABLES, Tag)                   tableTag;
    Vector#(`NUMTAGTABLES, UsefulCtr)             uCtr;
    Vector#(TAdd#(`NUMTAGTABLES,1), TagTableCtr)  ctr;
    GlobalHistory                                 ghr;
    Prediction                                    pred;
    TableNo                                       tableNo;
    AltPrediction                                 altpred;
    PathHistory                                   phr;
} PredictionPacket deriving(Bits, Eq, FShow);

typedef struct {
    BimodalIndex                                  bimodal_index;
    Vector#(`NUMTAGTABLES, TagTableIndex)         tagTable_index;
    Vector#(`NUMTAGTABLES, Tag)                   tableTag;
    Vector#(`NUMTAGTABLES, UsefulCtr)             uCtr;
    Vector#(TAdd#(`NUMTAGTABLES,1), TagTableCtr)  ctr;
    Prediction                                    pred;
    GlobalHistory                                 ghr;
    TableNo                                       tableNo;
    AltPrediction                                 altpred;
    Misprediction                                 mispred;
    ActualOutcome                                 actualOutcome;
    PathHistory                                   phr;
} UpdationPacket deriving(Bits,Eq, FShow);

typedef struct {
    Int#(32)                                      predictionCtr;
    Int#(32)                                      mispredictionCtr;
} TableCounters deriving(Bits, Eq, FShow);

function Bit#(64) compHistFn(GlobalHistory ghr, TargetLength targetlength, GeomLength geomlength);

    Bit#(32) mask = (1 << targetlength) - 32'b1;
    Bit#(32) mask1 = zeroExtend(ghr[geomlength]) << (geomlength % targetlength);
    Bit#(32) mask2 = (1 << targetlength);
    Bit#(32) compHist = 0;
    compHist = (compHist << 1) + zeroExtend(ghr[0]);
    compHist = compHist ^ ((compHist & mask2) >> targetlength);
    compHist = compHist ^ mask1;
    compHist = compHist & mask;
    return zeroExtend(compHist);
  endfunction



//verilog code history function definition
function Bit#(64) compFoldIndex(ProgramCounter pc, GlobalHistory ghr, PathHistory phr, TableNo ti);

        Bit#(64) index = 0;
        if (ti == 3'b000) begin
                index = pc[`BIMODAL_LEN - 1:0];        //13bit pc
            return index;
        end
        else if (ti == 3'b001) begin
      let comp_hist = compHistFn(ghr, `TABLE_LEN, `GHR1);
            index = pc ^ (pc >> `TABLE_LEN) ^ comp_hist ^ zeroExtend(phr) ^ (zeroExtend(phr) >> `TABLE_LEN); // indexTagPred[0] = PC ^ (PC >> TAGPREDLOG) ^ indexComp[0].compHist ^ PHR ^ (PHR >> TAGPREDLOG);
        return index;
        end
      else if (ti == 3'b010) begin
            let comp_hist =  compHistFn(ghr, `TABLE_LEN, `GHR2);
      index = pc ^ (pc >> (`TABLE_LEN - 1)) ^ comp_hist ^ zeroExtend(phr) ^ (zeroExtend(phr) >> `TABLE_LEN);
            return index;
        end
        else if (ti == 3'b011) begin
          let comp_hist = compHistFn(ghr, `TABLE_LEN, `GHR3);
      index = pc ^ (pc >> (`TABLE_LEN - 2)) ^ comp_hist ^ zeroExtend(phr) ^ (zeroExtend(phr) >> `TABLE_LEN);
            return index;
        end
        else begin
            let comp_hist = compHistFn(ghr, `TABLE_LEN, `GHR4);
      index = pc ^ (pc >> (`TABLE_LEN - 3)) ^ comp_hist ^ zeroExtend(phr) ^ (zeroExtend(phr) >> `TABLE_LEN);
          return index;
        end

endfunction

function Bit#(64) compFoldTag(ProgramCounter pc, GlobalHistory ghr, TableNo ti);
  Bit#(64) comp_tag_table = 0;
  if (ti == 3'b001) begin
    let comp_hist0 = compHistFn(ghr,`TAG2_SIZE, `GHR1);
    let comp_hist1 = compHistFn(ghr,`TAG1_SIZE, `GHR1);
    comp_tag_table = pc ^ comp_hist0 ^ (comp_hist1 << 1) ;
    return comp_tag_table;
    // tag[i] = PC ^ tagComp[0][i].compHist ^ (tagComp[1][i].compHist << 1);
  end
  else if (ti == 3'b010) begin
    let comp_hist0 = compHistFn(ghr,`TAG2_SIZE, `GHR2);
    let comp_hist1 = compHistFn(ghr,`TAG1_SIZE, `GHR2);
    comp_tag_table = pc ^ comp_hist0 ^ (comp_hist1 << 1) ;
    return comp_tag_table;
  end
  else if (ti == 3'b011) begin
    let comp_hist0 = compHistFn(ghr,`TAG2_SIZE, `GHR3);
    let comp_hist1 = compHistFn(ghr,`TAG1_SIZE, `GHR3);
    comp_tag_table = pc ^ comp_hist0 ^ (comp_hist1 << 1) ;
    return comp_tag_table;
  end
  else if (ti == 3'b100) begin
    let comp_hist0 = compHistFn(ghr,`TAG2_SIZE, `GHR4);
    let comp_hist1 = compHistFn(ghr,`TAG1_SIZE, `GHR4);
    comp_tag_table = pc ^ comp_hist0 ^ (comp_hist1 << 1) ;
    return comp_tag_table;
  end
  else
    return 0;

endfunction

endpackage
