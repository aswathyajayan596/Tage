package Type_TAGE;


import Vector :: *;
import FShow :: *;

export Type_TAGE :: *;
`include "parameter_tage.bsv"

typedef Bit#(`PC_LEN)                               ProgramCounter;               //64bits
typedef Bit#(TAdd#(`GHR4,1))                        GlobalHistory;                //131bits
typedef Bit#(TLog#(TAdd#(`NUMTAGTABLES,1)))         TableNo;                      // 000, 001, 010, 011, 100
typedef Bit#(TLog#(`BIMODALSIZE))                   BimodalIndex;                 //8bits
typedef Bit#(TLog#(`TABLESIZE))                     TagTableIndex;                //7bits
typedef Bit#(`BIMODAL_CTR_LEN)                      BimodalCtr;                   //2bits counter
typedef Bit#(`TAGTABLE_CTR_LEN)                     TagTableCtr;                  //3bits counter
typedef Bit#(`TAG1_CSR1_SIZE)                       TableTag1;                    //8bits
typedef Bit#(`TAG2_CSR1_SIZE)                       TableTag2;                    //9bits
typedef Bit#(`U_LEN)                                UsefulCtr;                    //2bits
typedef Bit#(`OUTCOME)                              ActualOutcome;                //1bit
typedef Bit#(`PRED)                                 Prediction;                   //1bit
typedef Bit#(`PRED)                                 AltPrediction;                //1bit
typedef Bit#(`PRED)                                 Misprediction;                //misprediction bit
typedef Bit#(`GEOM_LEN)                             GeomLength;                   //geomlength of each table
typedef Bit#(`TARGET_LEN)                           TargetLength;                 //targetlength
typedef Bit#(`PHR_LEN)                              PathHistory;                  
typedef Bit#(`PRED)                                 PC_bit;

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

typedef union tagged {
    Bit#(`TABLE_LEN)            CSR_index;
    Bit#(`TAG1_CSR1_SIZE)       CSR1_tag1;          //8 bit
    Bit#(`TAG1_CSR2_SIZE)       CSR2_tag1;          //7 bit
    Bit#(`TAG2_CSR1_SIZE)       CSR1_tag2;          //9 bit
    Bit#(`TAG2_CSR2_SIZE)       CSR2_tag2;          //8 bit
} CSR deriving (Bits, Eq, FShow);


typedef struct {
  Int#(10) geomLength;
  Int#(10) targetLength;
  CSR foldHist;
} FoldHist deriving (Bits, Eq, FShow);



typedef struct {
    BimodalIndex                                            bimodal_index;
    Vector#(`NUMTAGTABLES, TagTableIndex)                   tagTable_index;
    Vector#(`NUMTAGTABLES, Tag)                             tableTag;
    Vector#(`NUMTAGTABLES, UsefulCtr)                       uCtr;
    BimodalCtr                                              bCtr;
    Vector#(`NUMTAGTABLES, TagTableCtr)                     ctr;
    GlobalHistory                                           ghr;
    Prediction                                              pred;
    TableNo                                                 tableNo;
    AltPrediction                                           altpred;
    PathHistory                                             phr;
    Vector#(TSub#(`NUMTAGTABLES,1), CSR)                    index_csr;          //10bit
    Vector#(2,  CSR)                                        tag1_csr1;          //8 bit
    Vector#(2,  CSR)                                        tag1_csr2;          //7 bit
    Vector#(2,  CSR)                                        tag2_csr1;          //9 bit
    Vector#(2,  CSR)                                        tag2_csr2;          //8 bit
} PredictionPacket deriving(Bits, Eq, FShow);

typedef struct {
    BimodalIndex                                            bimodal_index;
    Vector#(`NUMTAGTABLES, TagTableIndex)                   tagTable_index;
    Vector#(`NUMTAGTABLES, Tag)                             tableTag;
    Vector#(`NUMTAGTABLES, UsefulCtr)                       uCtr;
    BimodalCtr                                              bCtr;
    Vector#(`NUMTAGTABLES, TagTableCtr)                     ctr;
    Prediction                                              pred;
    GlobalHistory                                           ghr;
    TableNo                                                 tableNo;
    AltPrediction                                           altpred;
    Misprediction                                           mispred;
    ActualOutcome                                           actualOutcome;
    PathHistory                                             phr;
    Vector#(TSub#(`NUMTAGTABLES,1), CSR)                    index_csr;          //10bit
    Vector#(2,  CSR)                                        tag1_csr1;          //8 bit
    Vector#(2,  CSR)                                        tag1_csr2;          //7 bit
    Vector#(2,  CSR)                                        tag2_csr1;          //9 bit
    Vector#(2,  CSR)                                        tag2_csr2;          //8 bit
} UpdationPacket deriving(Bits,Eq, FShow);

typedef struct {
    Int#(32)                                                predictionCtr;
    Int#(32)                                                mispredictionCtr;
} TableCounters deriving(Bits, Eq, FShow);

endpackage
