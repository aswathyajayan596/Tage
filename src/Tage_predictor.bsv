package Tage_predictor;

  import Utils :: *;
  import Type_TAGE :: *;
  import RegFile :: *;
  import Vector :: *;


  `include "parameter_tage.bsv"

  interface Tage_predictor_IFC;
      method Action computePrediction(ProgramCounter pc); //Indexing Table,Tag Computation, Comparison of Tag, Obtaining Prediction
      method Action updateTablePred(UpdationPacket upd_pkt); //Updation of Usefulness Counter and Prediction Counter, Allocation of new entries in case of misprediction
      method PredictionPacket output_packet(); // Method to Output the prediction packet.
      method Action displayInternal(Bool start_display);
  endinterface

 

  function GlobalHistory update_GHR(GlobalHistory t_ghr, Bit#(1) pred_or_outcome);
    t_ghr = (t_ghr << 1);
    t_ghr[0] = pred_or_outcome;
    return t_ghr;
  endfunction

  function PathHistory update_PHR(PathHistory t_phr, PC_bit t_pc);
    t_phr = (t_phr << 1);   
    t_phr[0] = t_pc;   
    return t_phr;
  endfunction
  
  
  
  
  (*synthesize*)
  module mkTage_predictor(Tage_predictor_IFC); 
    

    let b_max = fromInteger(`BIMODALSIZE-1);   //maximum size for Regfile of Bimodal Predictor Table
    let t_max = fromInteger(`TABLESIZE-1);       //maximum size for RegFile of Predictor tables

    Reg#(GlobalHistory) ghr <- mkReg(0);            //internal register to store GHR
    Reg#(PathHistory) phr <- mkReg(0);              //internal register to store PHR

    //RegFiles of Table Predictors in TAGE, one bimodal table predictor and four Tagged table predictors
    RegFile#(BimodalIndex, BimodalEntry) bimodal <- mkRegFile(0, b_max);   //bimodal table
    RegFile#(TagTableIndex, TagEntry) table_0 <- mkRegFile(0, t_max);        //tagged table 0
    RegFile#(TagTableIndex, TagEntry) table_1 <- mkRegFile(0, t_max);        //tagged table 1
    RegFile#(TagTableIndex, TagEntry) table_2 <- mkRegFile(0, t_max);        //tagged table 2
    RegFile#(TagTableIndex, TagEntry) table_3 <- mkRegFile(0, t_max);        //tagged table 3

    Vector#(TSub#(`NUMTAGTABLES,1), Reg#(CSR)) reg_index_csr  <-  replicateM(mkReg(unpack(0)));

    Vector#(2, Reg#(CSR))      reg_tag1_csr1   <-  replicateM(mkReg(unpack(0)));
    Vector#(2, Reg#(CSR))      reg_tag1_csr2   <-  replicateM(mkReg(unpack(0)));
    Vector#(2, Reg#(CSR))      reg_tag2_csr1   <-  replicateM(mkReg(unpack(0)));
    Vector#(2, Reg#(CSR))      reg_tag2_csr2   <-  replicateM(mkReg(unpack(0)));
    
    RegFile#(TagTableIndex, TagEntry) tagTables[`NUMTAGTABLES] = {table_0, table_1, table_2, table_3}; //array of Tagged table predictors  
    
    Reg#(PredictionPacket) pred_pkt <- mkReg(unpack(0));  //output register to store prediction packet
    
    //Wires to take in values between methods and rules.
    Wire#(GlobalHistory) dw_ghr <- mkDWire(0);        //Wire for global history register
    Wire#(PathHistory) dw_phr <- mkDWire(0);          //Wire for path history register
    Wire#(PC_bit) dw_pc_bit <- mkDWire(0);        //Wire for program counter
    Wire#(Prediction)  dw_pred <- mkDWire(0);         //wire for prediction
    Wire#(Misprediction) dw_mispred <- mkDWire(0); 
    Wire#(ActualOutcome) dw_outcome <- mkDWire(0);

    Wire#(Bool) dw_pred_over <- mkDWire(False);           //Wire to indicate prediction is over
    Wire#(Bool) dw_update_over <- mkDWire(False);         //Wire to indicate updation is over

    Reg#(Bool)     rf_resetting <- mkReg (False);
    Reg#(BimodalIndex)   b_indx <- mkReg(0);
    Reg#(TagTableIndex)   t_indx <- mkReg(0);
    Reg#(Bool) b_rst_cmplt <- mkReg(False);
    Reg#(Bool) t_rst_cmplt <- mkReg(False);

    //D Wires for Compressed Histories
    Wire#(Vector#(TSub#(`NUMTAGTABLES,1), CSR)) dw_index_csr <- mkDWire(unpack(0));
    Wire#(Vector#(2, CSR)) dw_tag1_csr1 <- mkDWire(unpack(0));
    Wire#(Vector#(2, CSR)) dw_tag1_csr2 <- mkDWire(unpack(0));
    Wire#(Vector#(2, CSR)) dw_tag2_csr1 <- mkDWire(unpack(0));
    Wire#(Vector#(2, CSR)) dw_tag2_csr2 <- mkDWire(unpack(0));

    //display Register
    Reg#(Bool) display_en <- mkReg(False);
    
    function debug_display();
      BimodalEntry b_entry = unpack(0);
      TagEntry t_entry = unpack(0);
      
      for (Integer i = 0; i < 6; i=i+1) begin
        let index1 = 10 + i;
        let index2 = 1025 + i;
        b_entry = bimodal.sub(index1);
        $display("%b", b_entry);
        $display("%b", bimodal.sub(index2));
        $display("%b", table_0.sub(index1));
        $display("%b", table_0.sub(index2));
        $display("%b", table_1.sub(index1));
        $display("%b", table_1.sub(index2));
        $display("%b", table_2.sub(index1));
        $display("%b", table_2.sub(index2));
        $display("%b", table_3.sub(index1));
        $display("%b", table_3.sub(index2));
        $display("%b", table_4.sub(index1));
        $display("%b\n", table_4.sub(index2));
      end
        $display("%b", table_0.sub(1023));
  
    endfunction
    

    function ActionValue#(Vector#(`NUMTAGTABLES, TagEntry)) allocate_entry(Vector#(`NUMTAGTABLES, TagEntry) entries, Integer tno, Vector#(`NUMTAGTABLES,Tag) tags, ActualOutcome outcome);
    actionvalue
      Bool allocate = False;
      for (Integer i = 3; i >= 0; i = i - 1) begin
              if(i >= tno) begin
                  if(entries[i].uCtr == 2'b0 && allocate == False) begin
                  `ifdef DEBUG_1
                    $fdisplay(fh, "Allocation %d", i);
                  `endif
                  entries[i].uCtr = 2'b0;
                  entries[i].tag = tags[i];
                  entries[i].ctr = (outcome == 1'b1) ? 3'b100 : 3'b011 ;
                  allocate = True;
              end
          end
      end
      if (allocate == False) begin
          for (Integer i = 0; i < `NUMTAGTABLES; i = i + 1) begin
              if (i > tno)
                  entries[i].uCtr = entries[i].uCtr - 2'b1;
          end
      end
      return entries;
    endactionvalue
  endfunction

    `ifdef TAGE_DISPLAY
      function Action check_u_counters(Vector#(`NUMTAGTABLES,TagEntry) entries);
        action
          Integer found = 0;
          for (Integer i=0; i<`NUMTAGTABLES; i=i+1) begin
            if (entries[i].uCtr > 0) begin
                found = found + 1;
            end
          end
          `ifdef TAGE_DISPLAY
          if (display) begin
            $fdisplay(fh, "Found value = %d", found);
          end
          `endif
          if(found == `NUMTAGTABLES) begin
          `ifdef TAGE_DISPLAY
            $fdisplay(fh, "Found value = %d", found);
            $fdisplay(fh, "Found all u>0", fshow(entries));
            $fdisplay(fh, "\n");
          `endif
          end
        endaction
      endfunction
    `endif


    function ActionValue#(Bit#(`TABLE_LEN)) update_individualCSRs(Bit#(1) geometric_max,Bit#(1) outcome, CSR fold_history, Int#(10) geomLength, Int#(10) targetLength);
      actionvalue
        Bit#(`TABLE_LEN) bits_fold_history = 0;


        case (fold_history) matches
          tagged CSR_index  .ind  : bits_fold_history = ind;
          tagged CSR1_tag1  .tag_11: bits_fold_history = zeroExtend(tag_11);
          tagged CSR1_tag2  .tag_12: bits_fold_history = zeroExtend(tag_12);
          tagged CSR2_tag1  .tag_21: bits_fold_history = zeroExtend(tag_21);
          tagged CSR2_tag2  .tag_22: bits_fold_history = zeroExtend(tag_22);
        endcase

        `ifdef CSR_display
          $fdisplay(fh, "\n\nInitial CSR value: %b", bits_fold_history, cur_cycle);
        `endif
        let index = geomLength % targetLength;
        let t_len = targetLength;
        let v_msb = bits_fold_history[t_len-1];
        bits_fold_history = (bits_fold_history << 1);
        `ifdef CSR_display
          $fdisplay(fh, "Circular Shifted CSR value: %b", bits_fold_history, cur_cycle);
        `endif

        bits_fold_history[0] = bits_fold_history[0] ^ outcome ^ v_msb;
        `ifdef CSR_display
          $fdisplay(fh, "Outcome = %b", outcome, cur_cycle);
          $fdisplay(fh, "Outcome added, CSR value: %b", bits_fold_history, cur_cycle);

          $fdisplay(fh, "Geometric max: %b", geometric_max, cur_cycle);  
          $fdisplay(fh, "Geometric max index: %d", index,cur_cycle);
        `endif
        bits_fold_history[index] = bits_fold_history[index] ^ geometric_max;
        
        `ifdef
          $fdisplay(fh, "Final CSR value: %b\n\n", bits_fold_history, cur_cycle);
        `endif

        return bits_fold_history;
      endactionvalue
      
    endfunction

    function Action updateCSRs (Bit#(1) ghr_bits[], Bool is_speculatve);
      action
        Integer glen[4] = { `GHR1, `GHR2, `GHR3, `GHR4 };

        if(is_speculatve) begin
          
          for (Integer i = 0; i < 3; i= i+1) begin
            let csr <- update_individualCSRs(ghr_bits[i+1], ghr_bits[4], reg_index_csr[i], fromInteger(glen[i+1]), `TABLE_LEN);
            reg_index_csr[i] <= tagged CSR_index csr;
            if( i < 2) begin
              let tag_csr <- update_individualCSRs(ghr_bits[i], ghr_bits[4], reg_tag1_csr1[i], fromInteger(glen[i]), fromInteger(`TAG1_CSR1_SIZE));
              reg_tag1_csr1[i] <= tagged CSR1_tag1 truncate(tag_csr);
              tag_csr <- update_individualCSRs(ghr_bits[i], ghr_bits[4], reg_tag1_csr2[i], fromInteger(glen[i]), fromInteger(`TAG1_CSR2_SIZE));
              reg_tag1_csr2[i] <= tagged CSR2_tag1 truncate(tag_csr);
              tag_csr <- update_individualCSRs(ghr_bits[i+2], ghr_bits[4], reg_tag2_csr1[i], fromInteger(glen[i+2]), fromInteger(`TAG2_CSR1_SIZE));
              reg_tag2_csr1[i] <= tagged CSR1_tag2 truncate(tag_csr);
              tag_csr <- update_individualCSRs(ghr_bits[i+2], ghr_bits[4], reg_tag2_csr2[i], fromInteger(glen[i+2]), fromInteger(`TAG2_CSR2_SIZE));
              reg_tag2_csr2[i] <= tagged CSR2_tag2 truncate(tag_csr);
            end
          end 
        end
        else begin
          for (Integer i = 0; i < 3; i= i+1) begin
            let csr <- update_individualCSRs(ghr_bits[i+1], ghr_bits[4], dw_index_csr[i], fromInteger(glen[i+1]), `TABLE_LEN);
            reg_index_csr[i] <= tagged CSR_index csr;
            if( i < 2) begin
              let tag_csr <- update_individualCSRs(ghr_bits[i], ghr_bits[4], dw_tag1_csr1[i], fromInteger(glen[i]), fromInteger(`TAG1_CSR1_SIZE));
              reg_tag1_csr1[i] <= tagged CSR1_tag1 truncate(tag_csr);
              tag_csr <- update_individualCSRs(ghr_bits[i], ghr_bits[4], dw_tag1_csr2[i], fromInteger(glen[i]), fromInteger(`TAG1_CSR2_SIZE));
              reg_tag1_csr2[i] <= tagged CSR2_tag1 truncate(tag_csr);
              tag_csr <- update_individualCSRs(ghr_bits[i+2], ghr_bits[4], dw_tag2_csr1[i], fromInteger(glen[i+2]), fromInteger(`TAG2_CSR1_SIZE));
              reg_tag2_csr1[i] <= tagged CSR1_tag2 truncate(tag_csr);
              tag_csr <- update_individualCSRs(ghr_bits[i+2], ghr_bits[4], dw_tag2_csr2[i], fromInteger(glen[i+2]), fromInteger(`TAG2_CSR2_SIZE));
              reg_tag2_csr2[i] <= tagged CSR2_tag2 truncate(tag_csr);
            end
          end
      end
          
      endaction
    endfunction

    function Bit#(`TABLE_LEN) compFoldIndex(ProgramCounter pc, TableNo ti);
      Bit#(`TABLE_LEN) index = 0;
      case (ti)
        3'b000 :  
                  index = pc[`BIMODAL_LEN:0]; 
        3'b001 :  
                  index = pc[9:0] ^ pc[19:10] ^ ghr[9:0] ^ phr[9:0] ^ zeroExtend(phr[15:10]);
        3'b010 : 
                  index = pc[9:0] ^ pc[18:9] ^ truncate(pack(reg_index_csr[0])) ^ phr[9:0] ^ zeroExtend(phr[15:10]);
        3'b011 : 
                  index = pc[9:0] ^ pc[17:8] ^ truncate(pack(reg_index_csr[1])) ^  phr[9:0] ^ zeroExtend(phr[15:10]);
                  
        3'b100 : 
                  index = pc[9:0] ^ pc[16:7] ^ truncate(pack(reg_index_csr[2])) ^ zeroExtend(phr[2:0]);
      endcase
      return index;
    endfunction

    function Bit#(`TAG2_CSR1_SIZE) compFoldTag(ProgramCounter pc, TableNo ti);
      Bit#(`TAG2_CSR1_SIZE) comp_tag_table = 0;
      case (ti) 
        3'b001 :  begin
                    Bit#(`TAG1_CSR1_SIZE) csr_1 = truncate(pack(reg_tag1_csr1[0]));
                    Bit#(`TAG1_CSR2_SIZE) csr_2 = truncate(pack(reg_tag1_csr2[0]));
                    comp_tag_table = zeroExtend(pc[7:0] ^ csr_1 ^ (zeroExtend(csr_2) << 1)) ;
                  end
        3'b010 :  begin
                    Bit#(`TAG1_CSR1_SIZE) csr_1 = truncate(pack(reg_tag1_csr1[1]));
                    Bit#(`TAG1_CSR2_SIZE) csr_2 = truncate(pack(reg_tag1_csr2[1]));
                    comp_tag_table = zeroExtend(pc[7:0] ^ csr_1 ^ (zeroExtend(csr_2) << 1)) ;
                  end
        3'b011 :  begin 
                    Bit#(`TAG2_CSR1_SIZE) csr_1 = truncate(pack(reg_tag2_csr1[0]));
                    Bit#(`TAG2_CSR2_SIZE) csr_2 = truncate(pack(reg_tag2_csr2[0]));
                    comp_tag_table = zeroExtend(pc[8:0] ^ csr_1 ^ (zeroExtend(csr_2) << 1)) ;  
                  end
        3'b100 :  begin
                    Bit#(`TAG2_CSR1_SIZE) csr_1 = truncate(pack(reg_tag2_csr1[1]));
                    Bit#(`TAG2_CSR2_SIZE) csr_2 = truncate(pack(reg_tag2_csr2[1]));
                    comp_tag_table = zeroExtend(pc[8:0] ^ csr_1 ^ (zeroExtend(csr_2) << 1)) ;
                  end
      endcase
      return comp_tag_table;
    endfunction

    let fh <- mkReg(InvalidFile) ;
    String dumpFile = "sim_results.txt" ;
    
    rule rl_fdisplay(fh == InvalidFile);

        $display("In fdisplay rule...", cur_cycle);

        File lfh <- $fopen( dumpFile, "w" ) ;
        if ( lfh == InvalidFile )
        begin
            $display("cannot open %s", dumpFile, cur_cycle);
            $finish(0);
        end
        fh <= lfh ;
    endrule


    /*
    * Rule:  rl_reset
    * --------------------
    * initialises the entries in all tables (bimodal and tagged tables) with zero. 
    *
    * RegFiles resetting.
    *
    * b_indx, t_indx : index of bimodal and tag tables respectively.   
    * 
    * b_rst_cmplt, t_rst_cmplt : True, indicates reset of 
    *                            respective tables are complete
    * rf_resetting : when both tables resets are complete, regfiles resetting gets True.
    * 
    */
    rule rl_reset(!rf_resetting);
    
      $display("In rule reset in TAGE...", cur_cycle);
      
      // reset value corresponding to Tag1
      let init1 = TagEntry { ctr : 3'b000, uCtr : 2'b00, tag : tagged Tag1 0 };
      
      // reset value corresponding to Tag2
      let init2 = TagEntry { ctr : 3'b000, uCtr : 2'b00, tag : tagged Tag2 0 };
      
      if (b_indx <= b_max) begin
        bimodal.upd(b_indx, unpack(2'b00)); 
        b_indx <= b_indx + 1;
      end
      if (t_indx <= t_max) begin
        table_0.upd(t_indx, init1);
        table_1.upd(t_indx, init1);
        table_2.upd(t_indx, init2);
        table_3.upd(t_indx, init2);
        t_indx <= t_indx + 1;
      end
      if (b_indx == b_max-1) // b_rst_cmplt get true in the last index. 
        b_rst_cmplt <= True;
      if (t_indx == t_max-1) // t_rst_cmplt get true in the last index. 
        t_rst_cmplt <= True;      
      if (b_rst_cmplt && t_rst_cmplt) begin
        rf_resetting <= True;

        `ifdef TAGE_DISPLAY
            if (display) begin
                $fdisplay(fh, "\nReset Over!",cur_cycle);
            end
        `endif
      end
    endrule

    //rule to update the GHR and PHR when actualoutcome is obtained.
    rule rl_update_GHR_PHR (rf_resetting);


      $display("In rule update GHR and PHR in TAGE", cur_cycle);


      PathHistory t_phr = 0;
      GlobalHistory t_ghr = 0;
      // Misprediction if occured, reconstruct GHR and PHR 
      if (dw_mispred == 1'b1) begin
        t_ghr = dw_ghr;
        t_ghr = update_GHR(t_ghr, dw_outcome);
        t_phr = dw_phr;
        Bit#(1) ghr_bits[5] = {t_ghr[`GHR1], t_ghr[`GHR2], t_ghr[`GHR3], dw_ghr[`GHR4-1], t_ghr[0]};  //130th bit of ghr before updation
        updateCSRs(ghr_bits, False);
      end
      else if(dw_pred_over) begin
        t_ghr = update_GHR(ghr, dw_pred);
        t_phr = update_PHR(phr, dw_pc_bit);        
        Bit#(1) ghr_bits[5] = {t_ghr[`GHR1], t_ghr[`GHR2], t_ghr[`GHR3], ghr[`GHR4-1], t_ghr[0]};
        updateCSRs(ghr_bits, True);
      end
      ghr <= t_ghr;
      phr <= t_phr;
    endrule

    
    method Action computePrediction(ProgramCounter pc) if (rf_resetting);

      $display("In compute Prediction method...", cur_cycle);

      `ifdef SCRIPT 
        if(display) begin
          $fdisplay(fh, "\nPC = %h  ", pc, cur_cycle);
        end
      `endif
      

      //tags
      Tag computedTag[`NUMTAGTABLES];
      for (Integer i = 0; i < `NUMTAGTABLES; i = i+1) begin
        if(i<2)
        computedTag[i] = tagged Tag1 0;
        else
        computedTag[i] = tagged Tag2 0;
      end
      
      //indexes
      BimodalIndex bimodal_index = 0;
      TagTableIndex tagTable_indexes[`NUMTAGTABLES] = { 0, 0, 0 , 0 };

      //variable to store temporary prediction packet
      PredictionPacket t_pred_pkt = unpack(0);

      //updating PHR in temporary prediction packet
      t_pred_pkt.phr = update_PHR(phr, pc[2]);

    
      for (Integer i = 0; i < 3; i=i+1) begin
        t_pred_pkt.index_csr[i] = reg_index_csr[i];
        if(i<2) begin
          t_pred_pkt.tag1_csr1[i] = reg_tag1_csr1[i];
          t_pred_pkt.tag1_csr2[i] = reg_tag1_csr2[i];
          t_pred_pkt.tag2_csr1[i] = reg_tag2_csr1[i];
          t_pred_pkt.tag2_csr2[i] = reg_tag2_csr2[i];
        end
      end

      //calling index computation function for each table and calling tag computation function for each table
      bimodal_index = compFoldIndex(pc,3'b000);
      t_pred_pkt.bimodal_index = bimodal_index;


      for (Integer i = 0; i < 4; i=i+1) begin
        TableNo tNo = fromInteger(i+1);
        tagTable_indexes[i] = compFoldIndex(pc,tNo);
        t_pred_pkt.tagTable_index[i] = tagTable_indexes[i];
        if(i<2) begin
          computedTag[i] = tagged Tag1 truncate(compFoldTag(pc,tNo));
          t_pred_pkt.tableTag[i] = computedTag[i];
        end
        else begin
          computedTag[i] = tagged Tag2 truncate(compFoldTag(pc,tNo));
          t_pred_pkt.tableTag[i] = computedTag[i];
        end
      end

      //comparison of tag with the longest history table, getting prediction from it and alternate prediction from second longest tag matching table 
      t_pred_pkt.tableNo = 3'b000;
      t_pred_pkt.altpred = bimodal.sub(bimodal_index).ctr[1];
      t_pred_pkt.pred = bimodal.sub(bimodal_index).ctr[1];
      t_pred_pkt.bCtr = bimodal.sub(bimodal_index).ctr;

      TableNo altTableNo = 0;
      
      TableTag2 matchedTag = 0;
      Bool matched = False;
      Bool altMatched = False;
      for (Integer i = 3; i >= 0; i=i-1) begin
        t_pred_pkt.ctr[i] = tagTables[i].sub(tagTable_indexes[i]).ctr;
        t_pred_pkt.uCtr[i] = tagTables[i].sub(tagTable_indexes[i]).uCtr; 
        if(tagTables[i].sub(tagTable_indexes[i]).tag == computedTag[i] && !matched) begin
          t_pred_pkt.pred = tagTables[i].sub(tagTable_indexes[i]).ctr[2];
          t_pred_pkt.tableNo = fromInteger(i+1);        
          matched = True;
          case (computedTag[i]) matches
            tagged Tag1  .tag1  : matchedTag = zeroExtend(tag1);
            tagged Tag2  .tag2  : matchedTag = tag2;
          endcase
        end
        else if(tagTables[i].sub(tagTable_indexes[i]).tag == computedTag[i] && matched && !altMatched) begin
          t_pred_pkt.altpred = tagTables[i].sub(tagTable_indexes[i]).ctr[2];
          altTableNo = fromInteger(i+1);
          altMatched = True;
        end
      end
      
      dw_pred <= t_pred_pkt.pred;              //setting RWire for corresponding GHR updation in the rule
      dw_pc_bit<=pc[2];

      t_pred_pkt.ghr = ghr;
      
      pred_pkt <= t_pred_pkt;                     //assigning temporary prediction packet to prediction packet vector register

      `ifdef SCRIPT
        if(display_en) begin
        $fdisplay(fh,"\n", cur_cycle);
        $fdisplay(fh,"P_packet");
        $fdisplay(fh, "%h", pc);
        $fdisplay(fh, "%b", t_pred_pkt.pred);
        $fdisplay(fh, "%b", t_pred_pkt.altpred);
        $fdisplay(fh, "%b", t_pred_pkt.tableNo);
        $fdisplay(fh, "%b", altTableNo); 
        $fdisplay(fh, "%b", t_pred_pkt.bCtr);
        for (Integer i = 0; i < `NUMTAGTABLES; i = i+1) begin
          $fdisplay(fh, "%b", t_pred_pkt.ctr[i]);
        end
        for (Integer i = 0; i < `NUMTAGTABLES; i = i+1) begin
          $fdisplay(fh, "%b", t_pred_pkt.uCtr[i]);
        end 
        $fdisplay(fh,"%b", matchedTag);     
        $fdisplay(fh, "%h", t_pred_pkt.bimodal_index);
        for(Integer i = 0; i < `NUMTAGTABLES; i = i+1) begin
            $fdisplay(fh, "%h", t_pred_pkt.tagTable_index[i]);
        end
        for (Integer i = 0 ; i < `NUMTAGTABLES; i = i+1) begin 
          case (t_pred_pkt.tableTag[i]) matches
              tagged Tag1  .tag1  : $fdisplay(fh, "%h",tag1);
              tagged Tag2  .tag2  : $fdisplay(fh, "%h",tag2);
          endcase
        end
        $fdisplay(fh, "%h",t_pred_pkt.phr);
        $fdisplay(fh, "%h",t_pred_pkt.ghr[130:0]);
      end
      `endif
      dw_pred_over <= True;            
    endmethod


    method Action updateTablePred(UpdationPacket upd_pkt) if (rf_resetting);  

      $display("In update table Predictors...", cur_cycle);
        
        dw_ghr <= upd_pkt.ghr;
        dw_phr <= upd_pkt.phr;
        dw_outcome <= upd_pkt.actualOutcome;
        dw_mispred <= upd_pkt.mispred;


        dw_index_csr <= upd_pkt.index_csr;
        
        dw_tag1_csr1  <= upd_pkt.tag1_csr1;
        
        dw_tag1_csr2  <= upd_pkt.tag1_csr2;
        
        dw_tag2_csr1  <= upd_pkt.tag2_csr1;
        
        dw_tag2_csr2  <= upd_pkt.tag2_csr2;
        
        //store the indexes of each entry of predictor tables from the updation packet
        //Store the corresponding indexed entry whose index is obtained from the updation packet

        
        BimodalEntry bimodal_entry = unpack(0);
        bimodal_entry = bimodal.sub(upd_pkt.bimodal_index);        //size of uctr field is 3 bits
        Vector#(`NUMTAGTABLES,TagEntry) tagTable_entries = unpack(0);
        for (Integer i=0; i < `NUMTAGTABLES; i=i+1) begin
          tagTable_entries[i] = tagTables[i].sub(upd_pkt.tagTable_index[i]);
        end
        


        TableNo tagtableNo = upd_pkt.tableNo-1;

        

        //store the actual outcome from the updation packet
        ActualOutcome outcome = upd_pkt.actualOutcome;



        //Updation of usefulness counter
        /* Usefulness counter is updated if the final prediction is different from alternate 
        prediction, u is incremented if the prediction is correct u is decremented otherwise */


        if (upd_pkt.pred != upd_pkt.altpred) begin
            if (upd_pkt.mispred == 1'b0 && tagtableNo != 3'b000)
                tagTable_entries[tagtableNo].uCtr = upd_pkt.uCtr[tagtableNo] + 2'b1;
            else
                tagTable_entries[tagtableNo].uCtr = upd_pkt.uCtr[tagtableNo] - 2'b1;
        end

        // updation of provider component's prediction counter
        /* Provider component's prediction counter is incremented if actual outcome is TAKEN and decremented if actual outcome is NOT TAKEN */
        if(upd_pkt.actualOutcome == 1'b1) begin
            if(upd_pkt.tableNo == 3'b000)
                bimodal_entry.ctr = (upd_pkt.bCtr < 2'b11) ? (upd_pkt.bCtr + 2'b01) : 2'b11 ;
            else
                tagTable_entries[tagtableNo].ctr = (upd_pkt.ctr[tagtableNo] < 3'b111 )?(upd_pkt.ctr[tagtableNo] + 3'b1): 3'b111;
        end
        else begin
            if(upd_pkt.tableNo == 3'b000)
                bimodal_entry.ctr = (upd_pkt.bCtr > 2'b00 )? (upd_pkt.bCtr - 2'b1) : 2'b00;
            else
                tagTable_entries[tagtableNo].ctr = (upd_pkt.ctr[tagtableNo] > 3'b000)?(upd_pkt.ctr[tagtableNo] - 3'b1): 3'b000;
        end

        //Allocation of new entries if there is a misprediction
        /* Allocate new entry, if there is any u = 0 (not useful entry) for tables with longer history 
        Three cases arise: all u>0 , one u = 0, more than one u = 0
        For all u > 0, decrement all the u counters, No need to allocate new entry
        For one u = 0, allocate new entry to that index
        For more than one u = 0, allocate new entry to that which has longer history
        For the newly allocated entry, prediction counter is set to Weakly TAKEN or Weakly NOT TAKEN.
        For the newly allocated entry, usefuleness counter is set to 0.
        For the newly allocated entry, tag is computed tag stored in the updation packet for that entry
        */
        

        if (upd_pkt.mispred == 1'b1) begin
            case (upd_pkt.tableNo)
                3'b000 :    tagTable_entries <- allocate_entry(tagTable_entries, 0, upd_pkt.tableTag, upd_pkt.actualOutcome);
                3'b001 :    tagTable_entries <- allocate_entry(tagTable_entries, 1, upd_pkt.tableTag, upd_pkt.actualOutcome);
                3'b010 :    tagTable_entries <- allocate_entry(tagTable_entries, 2, upd_pkt.tableTag, upd_pkt.actualOutcome);
                3'b011 :    tagTable_entries <- allocate_entry(tagTable_entries, 3, upd_pkt.tableTag, upd_pkt.actualOutcome);
            endcase
        end
        
    //Assigning back the corresponding entries to the prediction tables.
    bimodal.upd(upd_pkt.bimodal_index,bimodal_entry);
    for(Integer i = 0 ; i < `NUMTAGTABLES; i = i+1)
        tagTables[i].upd(upd_pkt.tagTable_index[i], tagTable_entries[i]);
    `ifdef SCRIPT
        if (display_en) begin
          $fdisplay(fh,"\n", cur_cycle);
          $fdisplay(fh,"U_packet");
          $fdisplay(fh,"PC");
          $fdisplay(fh, "%h",upd_pkt.actualOutcome);
          $fdisplay(fh, "%b", upd_pkt.altpred);
          $fdisplay(fh, "%b", upd_pkt.tableNo);
          $fdisplay(fh, "altTableNo");
          $fdisplay(fh, "%b", bimodal_entry.ctr);
          for (Integer i=0; i < `NUMTAGTABLES; i=i+1) begin
            $fdisplay(fh, "%b", tagTable_entries[i].ctr);
          end 
          for (Integer i=0; i < `NUMTAGTABLES; i=i+1) begin
            $fdisplay(fh, "%b", tagTable_entries[i].uCtr);
          end  
          $fdisplay(fh,"MatchedTag");    
          $fdisplay(fh, "%h", upd_pkt.bimodal_index);
          for(Integer i = 0;i < `NUMTAGTABLES; i = i+1) begin
            $fdisplay(fh, "%h", upd_pkt.tagTable_index[i]);
          end
          for (Integer i = 0 ; i < `NUMTAGTABLES; i = i+1) begin 
            case (tagTable_entries[i].tag) matches
                tagged Tag1  .tag1  : $fdisplay(fh, "%h",tag1);
                tagged Tag2  .tag2  : $fdisplay(fh, "%h",tag2);
            endcase
          end
          $fdisplay(fh, "%h",upd_pkt.phr);
          $fdisplay(fh, "%h",upd_pkt.ghr[130:0]);
        end
      `endif
    endmethod

    method PredictionPacket output_packet(); //method that outputs the prediction packet
      return pred_pkt;
    endmethod

    method Action displayInternal(Bool start_display);
        $display("In display internal method", cur_cycle);
        display_en <= start_display;
    endmethod

  endmodule

endpackage
