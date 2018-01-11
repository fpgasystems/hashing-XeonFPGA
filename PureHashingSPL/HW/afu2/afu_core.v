// Copyright (c) 2013-2015, Intel Corporation
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// * Redistributions of source code must retain the above copyright notice,
// this list of conditions and the following disclaimer.
// * Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation
// and/or other materials provided with the distribution.
// * Neither the name of Intel Corporation nor the names of its contributors
// may be used to endorse or promote products derived from this software
// without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.


`include "spl_defines.vh"


module afu_core (
    input  wire                             clk,
    input  wire                             reset_n,
    
    input  wire                             spl_enable,
    input  wire                             spl_reset,
    
    // TX_RD request, afu_core --> afu_io
    input  wire                             spl_tx_rd_almostfull,
    output reg                              cor_tx_rd_valid,
    output reg  [57:0]                      cor_tx_rd_addr,
    output reg  [5:0]                       cor_tx_rd_len,  // in CL, 0-64, 1-1, 2-2, ...63-63
    
    
    // TX_WR request, afu_core --> afu_io
    input  wire                             spl_tx_wr_almostfull,    
    output reg                              cor_tx_wr_valid,
    output reg                              cor_tx_dsr_valid,
    output reg                              cor_tx_fence_valid,
    output reg                              cor_tx_done_valid,
    output reg  [57:0]                      cor_tx_wr_addr, 
    output reg  [5:0]                       cor_tx_wr_len, 
    output reg  [511:0]                     cor_tx_data,
             
    // RX_RD response, afu_io --> afu_core
    input  wire                             io_rx_rd_valid,
    input  wire [511:0]                     io_rx_data,    
                 
    // afu_csr --> afu_core, afu_id
    input  wire                             csr_id_valid,
    output reg                              csr_id_done,    
    input  wire [31:0]                      csr_id_addr,
//    input  wire [63:0]                      csr_id,
    
    // afu_csr --> afu_core, afu_scratch
    input  wire                             csr_scratch_valid,
    output wire                             csr_scratch_done,    
    input  wire [31:0]                      csr_scratch_addr,
    input  wire [63:0]                      csr_scratch,
        
     // afu_csr --> afu_core, afu_ctx   
    input  wire                             csr_ctx_base_valid,
    input  wire [57:0]                      csr_ctx_base
);


    localparam [2:0]
        TX_RD_STATE_IDLE       = 3'b000,
        TX_RD_STATE_CTX        = 3'b001,
        TX_RD_STATE_LOAD       = 3'b010,
        TX_RD_STATE_START0     = 3'b011,
        TX_RD_STATE_START1     = 3'b100,
        TX_RD_STATE_RUN        = 3'b101,
        TX_RD_STATE_RUN1       = 3'b110;
        
    localparam [0:0]
        RX_RD_STATE__IDLE       = 1'b0,
        RX_RD_STATE__RUN        = 1'b1;
        
    localparam [2:0]
        TX_WR_STATE_IDLE       = 3'b000,
        TX_WR_STATE_CTX        = 3'b001,
        TX_WR_STATE_RUN        = 3'b010,
        TX_WR_STATE_STATUS     = 3'b011,
        TX_WR_STATE_FENCE      = 3'b100,
        TX_WR_STATE_TASKDONE   = 3'b101;
                        
    localparam [1:0]        
        RXQ_RD_STATE_IDLE      = 2'b00,
        RXQ_RD_STATE_0         = 2'b01,
        RXQ_RD_STATE_1         = 2'b10,
        RXQ_RD_STATE_2         = 2'b11;
                
                
    localparam [5:0]                
        AFU_CSR__LATENCY_CNT        = 6'b00_0100,
        AFU_CSR__PERFORMANCE_CNT    = 6'b00_0101;
               
    localparam AFU_ID               = 64'h111_00181;
                        
                        
    reg                             tx_wr_run;
    reg  [5:0]                      tx_wr_cnt;

    reg  [2:0]                      tx_rd_state;
    reg  [2:0]                      tx_wr_state;
    reg                             rx_rd_state;
    
    reg                             ctx_valid;
//    reg  [31:0]                     ctx_delay;
//    reg  [15:0]                     ctx_threshold;
    reg  [57:0]                     ctx_src_ptr;
    reg  [57:0]                     ctx_dst_ptr;
    reg  [31:0]                     ctx_length;
    
    reg  [31:0]                     src_cnt;
    
    reg                             tx_rd_valid;
    reg  [5:0]                      tx_rd_len;
    reg  [57:0]                     tx_rd_addr;
    reg  [57:0]                     tx_rd_addr_next;
    wire [6:0]                      tx_rd_addr_next_try;
    
    wire [6:0]                      tx_wr_addr_next_try;
    
    reg  [9:0]                      tr_pend_cnt;
    wire                            tr_pend_full;
    
    reg  [57:0]                     dst_ptr;
    reg  [31:0]                     dst_cnt;
        
    reg  [511:0]                    rxq_din;
    reg                             rxq_we;
    reg                             rxq_re;
    wire [511:0]                    rxq_dout;
    wire                            rxq_empty;
    wire                            rxq_almostempty;
    wire                            rxq_full    /* synthesis syn_keep=1 */;
    wire [3+`MAX_TRANSFER_SIZE:0]   rxq_count    /* synthesis syn_keep=1 */;
    wire                            rxq_almostfull;
    reg  [31:0]                     rxq_wr_cnt;
    reg  [31:0]                     rxq_rd_cnt;    
    reg  [1:0]                      rxq_rd_state;
    reg  [2:0]                      rxq_rd_active;
    
    reg  [3:0]                      tx_data_valid;
    
    reg  [3:0]                      tx_dsr_valid;

    reg  [3:0]                      dsr_valid;

    wire [31:0]                     dsr_latency_cnt_addr;
    wire [31:0]                     dsr_performance_cnt_addr;
    reg  [31:0]                     dsr_latency_cnt;
    reg  [31:0]                     dsr_performance_cnt;
        
    wire                            csr_id_update;
    wire                            csr_scratch_update;
    reg                             csr_scratch_done_tw;
    reg                             csr_scratch_done_rxq;
    
    reg  [57:0]                     status_addr;
    reg                             status_addr_valid;
    reg                             status_addr_cr;
    
    
`ifdef VENDOR_XILINX
    (* ram_extract = "no" *) reg  [511:0]                    tx_data[0:3];
    (* ram_extract = "no" *) reg  [31:0]                     tx_dsr_addr[0:3];
    (* ram_extract = "no" *) reg  [31:0]                     dsr_addr[0:3];        
    (* ram_extract = "no" *) reg  [63:0]                     dsr_data[0:3];    
`else
    (* ramstyle = "logic" *) reg  [511:0]                    tx_data[0:3];
    (* ramstyle = "logic" *) reg  [31:0]                     tx_dsr_addr[0:3];
    (* ramstyle = "logic" *) reg  [31:0]                     dsr_addr[0:3];        
    (* ramstyle = "logic" *) reg  [63:0]                     dsr_data[0:3]; 
`endif

    
    sim_fifo #(.FIFO_WIDTH(512),
               .FIFO_DEPTH_BITS(4+`MAX_TRANSFER_SIZE),       // transfer size 1 -> 32 entries
               .FIFO_ALMOSTFULL_THRESHOLD(2**(4+`MAX_TRANSFER_SIZE)-4),
               .FIFO_ALMOSTEMPTY_THRESHOLD(2)
              ) rxq(
        .clk                (clk),
        .reset_n            (reset_n & (~spl_reset)),
        .din                (rxq_din),
        .we                 (rxq_we),
        .re                 (rxq_re),
        .dout               (rxq_dout),
        .empty              (rxq_empty),
        .almostempty        (rxq_almostempty),
        .full               (rxq_full),
        .count              (rxq_count),
        .almostfull         (rxq_almostfull)
    );              

    wire [7:0]   my_out_valid;
    wire [19:0]  my_out_data_parts [7:0];
    wire [511:0] my_out_data;
    /*hash_function_h20bit hashing (
        .clk(clk),
        .resetn(reset_n),
        .req_hash(tx_data_valid[0]),
        .in_data(tx_data[0]),
        .out_valid(my_out_valid),
        .out_data(my_out_data)
    );*/
    generate
        genvar i;
        for(i=0; i<8; i=i+1) begin: st
            simple_tabulation_key64_hash20 stX (
            .clk(clk),
            .resetn(reset_n),
            .req_hash(tx_data_valid[0]),
            .in_data(tx_data[0][63+i*64:0+i*64]),
            .out_valid(my_out_valid[i]),
            .out_data(my_out_data_parts[i])
            );
        end
    endgenerate
    assign my_out_data = {  44'b0, my_out_data_parts[7],
                            44'b0, my_out_data_parts[6],
                            44'b0, my_out_data_parts[5],
                            44'b0, my_out_data_parts[4],
                            44'b0, my_out_data_parts[3],
                            44'b0, my_out_data_parts[2],
                            44'b0, my_out_data_parts[1],
                            44'b0, my_out_data_parts[0]};

    //-----------------------------------------------------------
    // TX_WR
    //-----------------------------------------------------------
    assign csr_id_update = csr_id_valid & (~csr_id_done) & (~spl_tx_wr_almostfull);
//    assign csr_scratch_update = csr_scratch_valid & (~csr_scratch_done) & (~spl_tx_wr_almostfull);
    assign csr_scratch_update = csr_scratch_valid & (~csr_scratch_done) & (~spl_tx_wr_almostfull);   // disable DSR insertion
    assign dsr_latency_cnt_addr = csr_id_addr + AFU_CSR__LATENCY_CNT;
    assign dsr_performance_cnt_addr = csr_id_addr + AFU_CSR__PERFORMANCE_CNT;
    assign csr_scratch_done = csr_scratch_done_tw | csr_scratch_done_rxq;
    assign tx_wr_addr_next_try = dst_ptr[5:0] + `MAX_TRANSFER_SIZE;
    
           
    always @(posedge clk) begin
        if ((~reset_n) | spl_reset) begin
            cor_tx_wr_valid <= 1'b0;
            cor_tx_dsr_valid <= 1'b0;
            cor_tx_fence_valid <= 1'b0;
            cor_tx_done_valid <= 1'b0;
            csr_id_done <= 1'b0;
            tx_wr_run <= 1'b0; 
            csr_scratch_done_tw <= 1'b0;
            tx_wr_state <= TX_WR_STATE_IDLE;
        end
        
        else begin
            cor_tx_wr_valid <= 1'b0;
            cor_tx_dsr_valid <= 1'b0;
            cor_tx_fence_valid <= 1'b0;
            csr_id_done <= 1'b0;
            csr_scratch_done_tw <= 1'b0;       

            case (tx_wr_state)
                TX_WR_STATE_IDLE : begin
                    if (csr_id_update) begin
                        cor_tx_wr_valid <= 1'b1;
                        cor_tx_dsr_valid <= 1'b1;
                        cor_tx_wr_len <= 6'h1;
                        cor_tx_wr_addr <= {26'b0, csr_id_addr};
                        cor_tx_data <= {448'b0, AFU_ID};
                        csr_id_done <= 1'b1;                    
                        tx_wr_state <= TX_WR_STATE_CTX;
                    end
                end
                
                TX_WR_STATE_CTX : begin
                    casex ({csr_scratch_update, ctx_valid})
                        2'b1? : begin
                            cor_tx_wr_valid <= 1'b1;
                            cor_tx_dsr_valid <= 1'b1;
                            cor_tx_wr_len <= 6'h1;
                            cor_tx_wr_addr <= {26'b0, csr_scratch_addr};
                            cor_tx_data <= {448'b0, csr_scratch};
                            csr_scratch_done_tw <= 1'b1;                    
                        end
                    
                        2'b01 : begin                                                            
                            dst_ptr <= ctx_dst_ptr;
                            dst_cnt <= ctx_length;
                            tx_wr_run <= 1'b1;
                            tx_wr_cnt <= 1'b0;
                            tx_wr_state <= TX_WR_STATE_RUN;
                        end
                    endcase                                        
                end //  TX_WR_STATE_CTX                                  

                TX_WR_STATE_RUN : begin
                    if (my_out_valid[0]) begin//if (tx_data_valid[0]) begin
                        cor_tx_wr_valid <= 1'b1;
                        cor_tx_wr_addr <= dst_ptr;                             
                        cor_tx_data <= my_out_data;//tx_data[0];
                        
                        if (tx_dsr_valid[0]) begin
                            cor_tx_wr_addr <= {26'b0, tx_dsr_addr[0]};
                            cor_tx_dsr_valid <= 1'b1; 
                            cor_tx_wr_len <= 6'h1;                       
                        end
                        
                        else begin
                            cor_tx_wr_addr <= dst_ptr;
//                            dst_ptr <= dst_ptr + 1'b1;
//                            dst_cnt <= dst_cnt - 1'b1;      
                                                            
                            if (tx_wr_cnt == 6'b0) begin    // driving header
                                if (dst_cnt >= `MAX_TRANSFER_SIZE) begin
                                    if (tx_wr_addr_next_try[6]) begin      // cross 4k boundary
                                        cor_tx_wr_len <= 1'b1;
                                        dst_cnt <= dst_cnt - 1'b1;   
                                        dst_ptr <= dst_ptr + 1'b1;
                                    end                                
                                    else begin  // not cross 4k boundary                                                                      
                                        cor_tx_wr_len <= `MAX_TRANSFER_SIZE;
                                        dst_cnt <= dst_cnt - `MAX_TRANSFER_SIZE;
                                        dst_ptr <= {dst_ptr[57:6], tx_wr_addr_next_try[5:0]};
                                        tx_wr_cnt <= `MAX_TRANSFER_SIZE - 1'b1;
                                    end                                
                                end
                                else begin
                                    cor_tx_wr_len <= 1'b1;
                                    dst_cnt <= dst_cnt - 1'b1;   
                                    dst_ptr <= dst_ptr + 1'b1;                                    
                                end                                                                                                                                                                                                                            
                            end
                            
                            else begin  // dring data
                                tx_wr_cnt <= tx_wr_cnt - 1'b1;
                                
                                // synthesis translate_off
                                assert(tx_wr_cnt > 0) else $fatal("driving too much data");
                                // synthesis translate_on                                                    
                            end
                        end                                                                                                
                    end 

                    else begin
                        if ((dst_cnt == 32'b0) & (tx_wr_cnt == 6'b0) & (~spl_tx_wr_almostfull)) begin
                            cor_tx_wr_valid <= 1'b1;
                            cor_tx_dsr_valid <= 1'b1;
                            cor_tx_wr_len <= 6'h1; 
                            cor_tx_wr_addr <= {26'b0, dsr_latency_cnt_addr};
                            cor_tx_data <= {448'b0, dsr_latency_cnt};
                            tx_wr_state <= TX_WR_STATE_STATUS;   
                        end
                    end                                  
                end    

                TX_WR_STATE_STATUS : begin
                    if (~spl_tx_wr_almostfull) begin
                        cor_tx_wr_valid <= 1'b1;
                        cor_tx_dsr_valid <= 1'b1;
                        cor_tx_wr_len <= 6'h1; 
                        cor_tx_wr_addr <= {26'b0, dsr_performance_cnt_addr};
                        cor_tx_data <= {448'b0, dsr_performance_cnt};
                        tx_wr_state <= TX_WR_STATE_FENCE;  
                    end
                end  
                
                TX_WR_STATE_FENCE : begin
                    if (~spl_tx_wr_almostfull) begin
                        cor_tx_wr_valid <= 1'b1;
                        cor_tx_fence_valid <= 1'b1;
                        tx_wr_state <= TX_WR_STATE_TASKDONE;  
                    end
                end  
                                
                TX_WR_STATE_TASKDONE : begin
                    if ((~spl_tx_wr_almostfull) & (~cor_tx_done_valid)) begin
                        cor_tx_wr_valid <= 1'b1;
                        cor_tx_done_valid <= 1'b1;
                        cor_tx_wr_len <= 6'h1;
                        cor_tx_wr_addr <= status_addr;
                        cor_tx_data[0] <= 1'b1;
                    end
                end  

            endcase                    
        end
    end
    
    
    //-----------------------------------------------------
    // read rxq
    //-----------------------------------------------------   
    always @(posedge clk) begin
        if ((~reset_n) | spl_reset) begin
            rxq_re <= 1'b0;
            rxq_rd_cnt <= 32'b0;
            tx_data_valid <= 4'b0;
            tx_dsr_valid <= 4'b0;
            dsr_valid <= 4'b0;
            rxq_rd_active <= 3'b0;
            csr_scratch_done_rxq <= 1'b0;
            rxq_rd_state <= RXQ_RD_STATE_IDLE;
        end
        
        else begin
            rxq_re <= 1'b0;
            csr_scratch_done_rxq <= 1'b0;

            tx_data_valid[3] <= tx_data_valid[2];
            tx_data_valid[2] <= tx_data_valid[1];
            tx_data_valid[1] <= tx_data_valid[0];
            tx_data[3] <= tx_data[2];
            tx_data[2] <= tx_data[1];
            tx_data[1] <= tx_data[0];
            tx_dsr_addr[3] <= tx_dsr_addr[2];
            tx_dsr_addr[2] <= tx_dsr_addr[1];
            tx_dsr_addr[1] <= tx_dsr_addr[0];
            tx_dsr_valid[3] <= tx_dsr_valid[2];
            tx_dsr_valid[2] <= tx_dsr_valid[1];
            tx_dsr_valid[1] <= tx_dsr_valid[0];
                              
            tx_data_valid[0] <= 1'b0;
            tx_dsr_valid[0] <= 1'b0; 
                                                                                                
            case (rxq_rd_state)
                RXQ_RD_STATE_IDLE : begin
                    if (tx_wr_run) rxq_rd_state <= RXQ_RD_STATE_0;
                end
                
                RXQ_RD_STATE_0 : begin
                    // thread 0, new rd or dsr
                    if (0) begin //*******************(csr_scratch_update & (rxq_rd_cnt[0] == 1'b0)) begin
                        dsr_valid[0] <= 1'b1;
                        dsr_addr[0] <= csr_scratch_addr;
                        dsr_data[0] <= csr_scratch;
                        csr_scratch_done_rxq <= 1'b1;                 
                        rxq_rd_active[0] <= 1'b1;
                    end                                                   
                    else if (((~rxq_re) & (~spl_tx_wr_almostfull) & (~rxq_empty)) |
                             (rxq_re & (~spl_tx_wr_almostfull) & (~rxq_almostempty))) begin
                        rxq_re <= 1'b1;      
                        rxq_rd_active[0] <= 1'b1;  
                        rxq_rd_cnt <= rxq_rd_cnt + 1'b1; 
                        dsr_valid[0] <= 1'b0;               
                    end
                    
                    // thread 1, data valid
                    if (rxq_rd_active[1]) begin
                        if (dsr_valid[1]) begin
                            tx_dsr_valid[0] <= 1'b1;
                            tx_dsr_addr[0] <= dsr_addr[1]; 
                            tx_data[0] <= {448'b0, dsr_data[1]};
                        end
                        else begin                        
                            tx_data[0] <= rxq_dout;
                        end
                        tx_data_valid[0] <= 1'b1;
                        rxq_rd_active[1] <= 1'b0;
                        dsr_valid[1] <= 1'b0; 
                    end
                                
                    // thread 2, reading
                                                            
                    rxq_rd_state <= RXQ_RD_STATE_1;                    
                end
                
                RXQ_RD_STATE_1 : begin
                    // thread 0, reading
                    
                    // thread 1, new rd or dsr
                    if (0) begin //******************(csr_scratch_update & (rxq_rd_cnt[0] == 1'b0)) begin
                        dsr_valid[1] <= 1'b1;
                        dsr_addr[1] <= csr_scratch_addr;
                        dsr_data[1] <= csr_scratch;
                        csr_scratch_done_rxq <= 1'b1;                 
                        rxq_rd_active[1] <= 1'b1;
                    end                               
                    else if (((~rxq_re) & (~spl_tx_wr_almostfull) & (~rxq_empty)) |
                             (rxq_re & (~spl_tx_wr_almostfull) & (~rxq_almostempty))) begin
                        rxq_re <= 1'b1; 
                        rxq_rd_active[1] <= 1'b1;  
                        rxq_rd_cnt <= rxq_rd_cnt + 1'b1; 
                        dsr_valid[1] <= 1'b0;                        
                    end        
                    
                    // thread 2, data valid
                    if (rxq_rd_active[2]) begin
                        if (dsr_valid[2]) begin
                            tx_dsr_valid[0] <= 1'b1;
                            tx_dsr_addr[0] <= dsr_addr[2]; 
                            tx_data[0] <= {448'b0, dsr_data[2]};
                        end
                        else begin                    
                            tx_data[0] <= rxq_dout;
                        end
                        
                        tx_data_valid[0] <= 1'b1;
                        rxq_rd_active[2] <= 1'b0;
                        dsr_valid[2] <= 1'b0; 
                    end

                    rxq_rd_state <= RXQ_RD_STATE_2;               
                end
                
                RXQ_RD_STATE_2 : begin
                    // thread 0, data valid
                    if (rxq_rd_active[0]) begin
                        if (dsr_valid[0]) begin
                            tx_dsr_valid[0] <= 1'b1;
                            tx_dsr_addr[0] <= dsr_addr[0]; 
                            tx_data[0] <= {448'b0, dsr_data[0]};
                        end
                        else begin                       
                            tx_data[0] <= rxq_dout;
                        end
                        
                        tx_data_valid[0] <= 1'b1;
                        rxq_rd_active[0] <= 1'b0;
                        dsr_valid[0] <= 1'b0; 
                    end
                    
                    // thread 1, reading
                    
                    // thread 2, new rd or dsr
                    if (0) begin //***************(csr_scratch_update & (rxq_rd_cnt[0] == 1'b0)) begin
                        dsr_valid[2] <= 1'b1;
                        dsr_addr[2] <= csr_scratch_addr;
                        dsr_data[2] <= csr_scratch;
                        csr_scratch_done_rxq <= 1'b1;                 
                        rxq_rd_active[2] <= 1'b1;
                    end                                          
                    else if (((~rxq_re) & (~spl_tx_wr_almostfull) & (~rxq_empty)) |
                             (rxq_re & (~spl_tx_wr_almostfull) & (~rxq_almostempty))) begin
                        rxq_re <= 1'b1; 
                        rxq_rd_active[2] <= 1'b1;  
                        rxq_rd_cnt <= rxq_rd_cnt + 1'b1;
                        dsr_valid[2] <= 1'b0;                              
                    end                            
                                        
                    rxq_rd_state <= RXQ_RD_STATE_0;
                end                                        
            endcase
        end
    end
            
    
    //-----------------------------------------------------
    // TX_RD request
    //-----------------------------------------------------    
    assign tx_rd_addr_next_try = tx_rd_addr_next[5:0] + `MAX_TRANSFER_SIZE;  //cfg_pagesize;
    
    always @(posedge clk) begin
        if ((~reset_n) | spl_reset) begin
            cor_tx_rd_valid <= 1'b0; 
            status_addr_valid <= 1'b0;
            status_addr_cr <= 1'b0;
            tx_rd_state <= TX_RD_STATE_IDLE;            
        end

        else begin
            cor_tx_rd_valid <= 1'b0;
            tx_rd_valid <= 1'b0;
            
            dsr_performance_cnt <= dsr_performance_cnt + 1'b1;
                    
            case (tx_rd_state)
                TX_RD_STATE_IDLE : begin
                    if (csr_ctx_base_valid & spl_enable & (~spl_tx_rd_almostfull) & (~rxq_almostfull) & (~tr_pend_full)) begin
                        cor_tx_rd_valid <= 1'b1;
                        cor_tx_rd_addr <= csr_ctx_base;
                        cor_tx_rd_len <= 6'h1;
                        dsr_latency_cnt <= 32'b0;
                        tx_rd_state <= TX_RD_STATE_CTX;
                                                
                        {status_addr_cr, status_addr[28:0]} <= csr_ctx_base[28:0] + 1'b1;
                    end
                end

                TX_RD_STATE_CTX : begin
                    if (~status_addr_valid) begin
                        status_addr_valid <= 1'b1;
                        status_addr[57:29] <= csr_ctx_base[57:29] + status_addr_cr;
                    end
                    
                    dsr_latency_cnt <= dsr_latency_cnt + 1'b1;
                    
                    if (ctx_valid) begin                     
                        tx_rd_addr_next <= ctx_src_ptr;
                        src_cnt <= ctx_length;  // - 1'b1;
                        
                        dsr_performance_cnt <= 32'b0;                                                
                        tx_rd_state <= TX_RD_STATE_RUN;
                    end
                end                    
                                
                TX_RD_STATE_RUN : begin
                    // ready to drive tx_rd
                    if (tx_rd_valid) begin                                                            
                        cor_tx_rd_valid <= 1'b1; 
                        cor_tx_rd_len <= tx_rd_len;
                        cor_tx_rd_addr <= tx_rd_addr;
                    end
                                            
                    // prepare next
                    if ((src_cnt > 32'b0) & (~spl_tx_rd_almostfull) & (~rxq_almostfull) & (~tr_pend_full)) begin
                        tx_rd_valid <= 1'b1;

                        if (src_cnt >= `MAX_TRANSFER_SIZE) begin     
                            if (tx_rd_addr_next_try[6]) begin      // cross 4k boundary
                                tx_rd_len <= 1'b1;
//                                tx_rd_addr <= tx_rd_addr + 1'b1;
                                tx_rd_addr <= tx_rd_addr_next;
                                tx_rd_addr_next <= tx_rd_addr_next + 1'b1;       
                                src_cnt <= src_cnt - 1'b1;
                            end
                            
                            else begin  // not cross 4k boundary                                
                                tx_rd_len <= `MAX_TRANSFER_SIZE;
                                tx_rd_addr <= tx_rd_addr_next;
                                tx_rd_addr_next <= {tx_rd_addr_next[57:6], tx_rd_addr_next_try[5:0]};
                                src_cnt <= src_cnt - `MAX_TRANSFER_SIZE;
                            end
                        end
                        else begin
                            tx_rd_len <= 1'b1;
                            tx_rd_addr <= tx_rd_addr_next;
                            tx_rd_addr_next <= tx_rd_addr_next + 1'b1; 
                            src_cnt <= src_cnt - 1'b1;                        
                        end
                    end                         
                end    
            endcase                    
        end
    end   
    
                    
    //-------------------------------------------------
    // RX_RD response
    //-------------------------------------------------  
    always @(posedge clk) begin
        if ((~reset_n) | spl_reset)begin
            ctx_valid <= 1'b0;
            rxq_we <= 1'b0;
            rxq_wr_cnt <= 32'b0;
            rx_rd_state <= RX_RD_STATE__IDLE;
        end

        else begin
            rxq_we <= 1'b0;
        
            case (rx_rd_state)             
                RX_RD_STATE__IDLE : begin
                    if (io_rx_rd_valid) begin
//                        ctx_delay <= io_rx_data[63:32];
//                        ctx_threshold <= io_rx_data[31:16];
                        ctx_src_ptr <= io_rx_data[127:70];
                        ctx_dst_ptr <= io_rx_data[191:134];
                        ctx_length <= io_rx_data[223:192];    
                        ctx_valid <= 1'b1;
                        rx_rd_state <= RX_RD_STATE__RUN;
                    end
                end

                RX_RD_STATE__RUN : begin
                    if (io_rx_rd_valid) begin
                        rxq_we <= 1'b1;
                        rxq_din <= io_rx_data;                        
                        
                        rxq_wr_cnt <= rxq_wr_cnt + 1'b1;
                    end
                end

            endcase
        end
    end   


    //-------------------------------------------------
    // tracking pending RD
    //-------------------------------------------------  
    assign tr_pend_full = (tr_pend_cnt >= 2**(4+`MAX_TRANSFER_SIZE) - 2**(1+`MAX_TRANSFER_SIZE)); //6'h1e);
    
    always @(posedge clk) begin
        if ((~reset_n) | spl_reset) begin
            tr_pend_cnt <= 10'b0;        
        end

        else begin
//            case ({cor_tx_rd_valid, io_rx_rd_valid})
            case ({cor_tx_rd_valid, rxq_re})
                2'b01 : begin
                    tr_pend_cnt <= tr_pend_cnt - 1'b1;
                    
                    // synthesis translate_off
                    assert(tr_pend_cnt != 0) else $fatal("received new RX_RD while no pending TX_RD");
                    // synthesis translate_on                    
                end
                
                2'b10 : begin
                    tr_pend_cnt <= tr_pend_cnt + cor_tx_rd_len;     //1'b1;
                    
                    // synthesis translate_off
                    assert(tr_pend_cnt < 2**(4+`MAX_TRANSFER_SIZE)) else $fatal("trying to generate new TX_RD while the limit is hit");
                    // synthesis translate_on                                        
                end
                
                2'b11 : begin
                    tr_pend_cnt <= tr_pend_cnt + cor_tx_rd_len - 1'b1;     //1'b1;
                    
                    // synthesis translate_off
                    assert(tr_pend_cnt < 2**(4+`MAX_TRANSFER_SIZE)) else $fatal("trying to generate new TX_RD while the limit is hit");
                    // synthesis translate_on                                        
                end 
                               
                default : begin
                    // no change
                end
            endcase
        end
    end
        
endmodule        

