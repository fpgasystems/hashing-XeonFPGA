// ***************************************************************************
//
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
//
// Engineer:            Pratik Marolia
// Create Date:         Thu Jul 28 20:31:17 PDT 2011
// Module Name:         test_lpbk2.v
// Project:             NLB AFU 
// Description:         cache coherency test
//
// ***************************************************************************
// ---------------------------------------------------------------------------------------------------------------------------------------------------
//                                         Loopback 2 test - cache coherency
//  ------------------------------------------------------------------------------------------------------------------------------------------------
//
// Upper Limit on # cache lines = 128
// This is a continuous test. The test ends only when it detects an error or it is reset
//
// This is a coherency test
// addr[0] = 1- Line is owned by FPGA
// addr[0] = 0- Line is owned by CPU
//
// Determinitistic data field
// data[31:0] = data[256+31:256] = addr
//
// How does the test generate the random field? Data[64:32]
// a simple wrap around counter is used to generate the mdata field. It is stored in sd_mem.
//


module test_lpbk2 #(parameter PEND_THRESH=1, ADDR_LMT=20, MDATA=14)
(

//      ---------------------------global signals-------------------------------------------------
       Clk_32UI               ,        // in    std_logic;  -- Core clock
       Resetb                 ,        // in    std_logic;  -- Use SPARINGLY only for control

       l22ab_WrAddr,                   // [ADDR_LMT-1:0]        arb:               write address
       l22ab_WrTID,                    // [ADDR_LMT-1:0]        arb:               meta data
       l22ab_WrDin,                    // [511:0]               arb:               Cache line data
       l22ab_WrEn,                     //                       arb:               write enable
       ab2l2_WrSent,                   //                       arb:               write issued
       ab2l2_WrAlmFull,                //                       arb:               write fifo almost full
       
       l22ab_RdAddr,                   // [ADDR_LMT-1:0]        arb:               Reads may yield to writes
       l22ab_RdTID,                    // [13:0]                arb:               meta data
       l22ab_RdEn,                     //                       arb:               read enable
       ab2l2_RdSent,                   //                       arb:               read issued

       ab2l2_RdRspValid,               //                       arb:               read response valid
       ab2l2_RdRsp,                    // [13:0]                arb:               read response header
       ab2l2_RdRspAddr,                // [ADDR_LMT-1:0]        arb:               read response address
       ab2l2_RdData,                   // [511:0]               arb:               read data

       ab2l2_WrRspValid,               //                       arb:               write response valid
       ab2l2_WrRsp,                    // [13:0]                arb:               write response header
       ab2l2_WrRspAddr,                // [ADDR_LMT-1:0]        arb:               write response address
       re2xy_go,                       //                       requestor:         start the test
       re2xy_src_addr,                 // [31:0]                requestor:         src address
       re2xy_dst_addr,                 // [31:0]                requestor:         destination address
       re2xy_NumLines,                 // [31:0]                requestor:         number of cache lines
       re2xy_Cont,                     //                       requestor:         continuous mode

       l22ab_TestCmp,                  //                       arb:               Test completion flag
       l22ab_ErrorInfo,                // [255:0]               arb:               error information
       l22ab_ErrorValid,               //                       arb:               test has detected an error
       test_Resetb                     //                       requestor:         rest the app
);
    input                   Clk_32UI;               //                      csi_top:            Clk_32UI
    input                   Resetb;                 //                      csi_top:            system Resetb
    
    output  [ADDR_LMT-1:0]  l22ab_WrAddr;           // [ADDR_LMT-1:0]        arb:               write address
    output  [13:0]          l22ab_WrTID;            // [13:0]                arb:               meta data
    output  [511:0]         l22ab_WrDin;            // [511:0]               arb:               Cache line data
    output                  l22ab_WrEn;             //                       arb:               write enable
    input                   ab2l2_WrSent;           //                       arb:               write issued
    input                   ab2l2_WrAlmFull;        //                       arb:               write fifo almost full
           
    output  [ADDR_LMT-1:0]  l22ab_RdAddr;           // [ADDR_LMT-1:0]        arb:               Reads may yield to writes
    output  [13:0]          l22ab_RdTID;            // [13:0]                arb:               meta data
    output                  l22ab_RdEn;             //                       arb:               read enable
    input                   ab2l2_RdSent;           //                       arb:               read issued
    
    input                   ab2l2_RdRspValid;       //                       arb:               read response valid
    input  [13:0]           ab2l2_RdRsp;            // [13:0]                arb:               read response header
    input  [ADDR_LMT-1:0]   ab2l2_RdRspAddr;        // [ADDR_LMT-1:0]        arb:               read response address
    input  [511:0]          ab2l2_RdData;           // [511:0]               arb:               read data
    
    input                   ab2l2_WrRspValid;       //                       arb:               write response valid
    input  [13:0]           ab2l2_WrRsp;            // [13:0]                arb:               write response header
    input  [ADDR_LMT-1:0]   ab2l2_WrRspAddr;        // [Addr_LMT-1:0]        arb:               write response address
    
    input                   re2xy_go;               //                       requestor:         start of frame recvd
    input  [31:0]           re2xy_src_addr;         // [31:0]                requestor:         src address
    input  [31:0]           re2xy_dst_addr;         // [31:0]                requestor:         destination address
    input  [31:0]           re2xy_NumLines;         // [31:0]                requestor:         number of cache lines
    input                   re2xy_Cont;             //                       requestor:         continuous mode
    
    output                  l22ab_TestCmp;          //                       arb:               Test completion flag
    output [255:0]          l22ab_ErrorInfo;        // [255:0]               arb:               error information
    output                  l22ab_ErrorValid;       //                       arb:               test has detected an error
    input                   test_Resetb;
    //------------------------------------------------------------------------------------------------------------------------
    localparam              MAX_LINES = 7;          // ->2^7 = 128
    localparam              ADDR_LMT_INV = 32- ADDR_LMT;
    localparam              BITPOS = 'd0;
    
    reg     [ADDR_LMT-1:0]  l22ab_WrAddr;           // [ADDR_LMT-1:0]        arb:               Writes are guaranteed to be accepted
    reg     [13:0]          l22ab_WrTID;            // [13:0]                arb:               meta data
    reg     [511:0]         l22ab_WrDin;            // [511:0]               arb:               Cache line data
    reg                     l22ab_WrEn;             //                       arb:               write enable
    reg     [ADDR_LMT-1:0]  l22ab_RdAddr;           // [ADDR_LMT-1:0]        arb:               Reads may yield to writes
    reg     [13:0]          l22ab_RdTID;            // [13:0]                arb:               meta data
    reg                     l22ab_RdEn;             //                       arb:               read enable
    reg                     l22ab_TestCmp;          //                       arb:               Test completion flag
    reg     [255:0]         l22ab_ErrorInfo;        // [255:0]               arb:               error information
    reg                     l22ab_ErrorValid;       //                       arb:               test has detected an error
    reg                     ab2l2_RdRspValid_q;     //                       arb:               read response valid
    reg    [ADDR_LMT-1:0]   ab2l2_RdRspAddr_q;      // [ADDR_LMT-1:0]        arb:               read response address
    reg    [511:0]          ab2l2_RdData_q;         // [511:0]               arb:               read data
    reg     [MAX_LINES-1:0] rdcnt, rdcnt_q;
    reg     [MAX_LINES-1:0] wrcnt, wrcnt_q;
    reg     [31:0]          expected_addr;
    
    wire [2**MAX_LINES-1:0] rdReq_valid;
    wire [2**MAX_LINES-1:0] wrReq_valid;
    reg  [7:0]              req_seed;
    reg  [2**MAX_LINES-1:0] req_sent;
    reg  [2**MAX_LINES-1:0] req_cmp;
    reg  [2**MAX_LINES-1:0] req_cmp_d;
    
    reg  [ADDR_LMT-1:0]     rdAddr;
    reg  [ADDR_LMT-1:0]     wrAddr;
    wire [ADDR_LMT-1:0]     sdmem_waddr = ~(14'h3fff<<MDATA) & (l22ab_WrAddr>>BITPOS);
    wire                    sdmem_we    = l22ab_WrEn;
    wire [7:0]              sdmem_wdin  = l22ab_WrDin[32+7:32];
    wire [ADDR_LMT-1:0]     sdmem_raddr = ~(14'h3fff<<MDATA) & (ab2l2_RdRspAddr>>BITPOS);
    wire [7:0]              sdmem_dout;
    integer i;
    
    generate
    genvar n;
        for (n=0;n<2**MAX_LINES;n=n+1)
        begin : gen_submodule_lpbk3
            submodule_lpbk2 #(.MODULE_ID(n)) submodule_lpbk3
            (
                    .Clk_32UI    (Clk_32UI),
                    .test_Resetb (test_Resetb),
                    .rdReq_valid (rdReq_valid[n]),
                    .wrReq_valid (wrReq_valid[n]),
                    .req_sent    (req_sent[n]),
                    .req_cmp     (req_cmp[n])
            );
        
        end
    endgenerate
    
    always @(*)
    begin
            for(i=0;i<2**MAX_LINES; i=i+1)
            begin
                    req_sent [i] = 0;
                    req_cmp_d[i] = 0;
            end
            
            l22ab_WrDin     = {{6{32'hf0f0_f0f0}},{4{~req_seed}},(re2xy_dst_addr^l22ab_WrAddr),
                               {6{32'hf0f0_f0f0}},{4{ req_seed}},(re2xy_dst_addr^l22ab_WrAddr)};
    
            if(l22ab_WrEn && ab2l2_WrSent)
                    req_sent[wrcnt_q] = 1;
            if(l22ab_RdEn && ab2l2_RdSent)
                    req_sent[rdcnt_q] = 1;
    
            if(ab2l2_RdRspValid)
                    req_cmp_d[ab2l2_RdRspAddr>>BITPOS] = 1;
            if(ab2l2_WrRspValid)
                    req_cmp_d[ab2l2_WrRspAddr>>BITPOS] = 1;
    end
    
    always @(posedge Clk_32UI)
    begin
            if(!test_Resetb)
            begin
                    l22ab_TestCmp           <= 0;
                    l22ab_ErrorInfo         <= 0;
                    l22ab_ErrorValid        <= 0;
                    ab2l2_RdRspValid_q      <= 0;
                    ab2l2_RdRspAddr_q       <= 0;
                    ab2l2_RdData_q          <= 0;
                    req_cmp                 <= 0;
                    rdcnt                   <= 0;
                    wrcnt                   <= 1;
                    rdcnt_q                 <= 0;
                    wrcnt_q                 <= 0;
                    rdAddr                  <= 0;
                    wrAddr                  <= (20'h1<<BITPOS);
                    expected_addr           <= 0;
                    req_seed                <= 8'h1;
                    l22ab_WrEn              <= 0;
                    l22ab_RdEn              <= 0;
                    l22ab_WrAddr            <= 0;
                    l22ab_RdAddr            <= 0;
                    l22ab_WrTID             <= 0;
                    l22ab_RdTID             <= 0;
            end
            else
            begin
                    ab2l2_RdRspValid_q      <= ab2l2_RdRspValid;
                    ab2l2_RdRspAddr_q       <= ab2l2_RdRspAddr;
                    ab2l2_RdData_q          <= ab2l2_RdData;
                    expected_addr           <= ab2l2_RdRspAddr ^ re2xy_dst_addr;
                    
                    req_seed    <= (req_seed<<1) | {5'h00,(req_seed[3] ^ req_seed[4] ^ req_seed[5] ^ req_seed[7])};
    
                    l22ab_WrAddr    <= wrAddr;
                    l22ab_RdAddr    <= rdAddr;
                    l22ab_WrTID     <= ~(14'h3fff<<MDATA) & wrcnt;
                    l22ab_RdTID     <= ~(14'h3fff<<MDATA) & rdcnt;
    
                    rdcnt_q         <= rdcnt;
                    wrcnt_q         <= wrcnt;
    
                    if(re2xy_go)
                    begin                                    
    
                            l22ab_WrEn      <= wrReq_valid[wrcnt];
                            l22ab_RdEn      <= rdReq_valid[rdcnt];
    
                            if(rdcnt<re2xy_NumLines-1)                                                      // read even and odd lines
                            begin
                                    rdcnt           <= rdcnt + 1'b1;
                                    rdAddr          <= rdAddr + (20'h1<<BITPOS);
                            end
                            else
                            begin
                                    rdcnt           <= 0;
                                    rdAddr          <= 0;
                            end
                            
                            if(wrcnt<re2xy_NumLines-1)                                                 // write odd lines only
                            begin
                                    wrcnt     <= wrcnt + 2'h2;
                                    wrAddr    <= wrAddr + (20'h1<<(BITPOS+1));
                            end
                            else
                            begin
                                    wrcnt     <= 1;
                                    wrAddr    <= (20'h1<<BITPOS);
                            end
    
                           if(re2xy_NumLines<=1)                                                            // line count should be greater than equal to 1.
                           begin
                                    l22ab_ErrorInfo[5:0]            <= 6'b10_0000;
                                    l22ab_ErrorValid                <= 1;
                           end
                    end
                    else
                    begin
                            l22ab_WrEn      <= 0;
                            l22ab_RdEn      <= 0;
                    end
                    
                    req_cmp <= req_cmp_d;
                    
                    // Read Data Check
                    if(l22ab_ErrorValid==0 && ab2l2_RdRspValid_q)
                    begin
                            l22ab_ErrorInfo[2*32-1:1*32]    <= expected_addr;                       // address
                            if(ab2l2_RdRspAddr_q[BITPOS]==1)                                                                // FPGA Owned
                            begin
            
                                    if(ab2l2_RdData_q[2*32-1:1*32] != {4{sdmem_dout}})
                                    begin
                                            l22ab_ErrorInfo[4:0]            <= 5'b01000;
                                            l22ab_ErrorInfo[8]              <= 1'b1;
                                            l22ab_ErrorValid                <= 1;
                                            l22ab_ErrorInfo[3*32-1:2*32]    <= ab2l2_RdData_q[2*32-1:1*32];         // Received data
                                            l22ab_ErrorInfo[4*32-1:3*32]    <= {4{sdmem_dout}};                     // Expected data
                                    end
                                    if(ab2l2_RdData_q[10*32-1:9*32] != {4{~sdmem_dout}})
                                    begin
                                            l22ab_ErrorInfo[4:0]            <= 5'b01000;
                                            l22ab_ErrorInfo[9]              <= 1'b1;
                                            l22ab_ErrorValid                <= 1;
                                            l22ab_ErrorInfo[5*32-1:4*32]    <= ab2l2_RdData_q[10*32-1:9*32];        // Received data
                                            l22ab_ErrorInfo[6*32-1:5*32]    <= {4{~sdmem_dout}};                    // Expected data
                                    end
                                    if(ab2l2_RdData_q[1*32-1:0*32] != expected_addr)
                                    begin
                                            l22ab_ErrorInfo[4:0]            <= 5'b01000;
                                            l22ab_ErrorInfo[10]             <= 1'b1;
                                            l22ab_ErrorValid                <= 1;
                                            l22ab_ErrorInfo[7*32-1:6*32]    <= ab2l2_RdData_q[1*32-1:0*32];         // Received data
    //                                        l22ab_ErrorInfo[4*32-1:3*32]    <= expected_addr;                       // Expected data
                                    end
                                    if(ab2l2_RdData_q[9*32-1:8*32] != expected_addr)
                                    begin
                                            l22ab_ErrorInfo[4:0]            <= 5'b01000;
                                            l22ab_ErrorInfo[11]             <= 1'b1;
                                            l22ab_ErrorValid                <= 1;
                                            l22ab_ErrorInfo[8*32-1:7*32]    <= ab2l2_RdData_q[9*32-1:8*32];         // Received data
    //                                        l22ab_ErrorInfo[4*32-1:3*32]    <= expected_addr;                       // Expected data
                                    end
            
                    end
                    else                                                                                    // CPU Owned
                    begin
                                    if(ab2l2_RdData_q[1*32-1:0*32] != expected_addr)
                                    begin
                                            l22ab_ErrorInfo[4:0]            <= 5'b11000;
                                            l22ab_ErrorInfo[12]             <= 1'b1;
                                            l22ab_ErrorValid                <= 1;
                                            l22ab_ErrorInfo[7*32-1:6*32]    <= ab2l2_RdData_q[1*32-1:0*32];         // Received data
    //                                        l22ab_ErrorInfo[4*32-1:3*32]    <= expected_addr;                       // Expected data
                                    end
                                    if(ab2l2_RdData_q[9*32-1:8*32] != expected_addr)
                                    begin
                                            l22ab_ErrorInfo[4:0]            <= 5'b11000;
                                            l22ab_ErrorValid                <= 1;
                                            l22ab_ErrorInfo[13]             <= 1'b1;
                                            l22ab_ErrorInfo[8*32-1:7*32]    <= ab2l2_RdData_q[9*32-1:8*32];         // Received data
    //                                        l22ab_ErrorInfo[4*32-1:3*32]    <= expected_addr;                       // Expected data
                                    end
                            end
                    end
            end
    
    end
    
    // stores the seed used to generate random data
    nlb_gram_sdp #(.BUS_SIZE_ADDR(MDATA),
              .BUS_SIZE_DATA(8),
              .GRAM_MODE(2'd1)
              )
    seed_mem (
                    .clk  (Clk_32UI),
                    .we   (sdmem_we),        
                    .waddr(sdmem_waddr[MDATA-1:0]),     
                    .din  (sdmem_wdin),       
                    .raddr(sdmem_raddr[MDATA-1:0]),     
                    .dout (sdmem_dout )
            );     
    
endmodule

module submodule_lpbk2 #(parameter MODULE_ID=0)
(
        Clk_32UI,
        test_Resetb,
        rdReq_valid,
        wrReq_valid,
        req_sent,
        req_cmp
);
    input           Clk_32UI;
    input           test_Resetb;
    output          rdReq_valid;
    output          wrReq_valid;
    input           req_sent;
    input           req_cmp;
    
    localparam      RD_PEND = 2'h0;
    localparam      WR_PEND = 2'h1;
    localparam      SEND_RD = 2'h2;
    localparam      SEND_WR = 2'h3;
    
    reg [1:0]       fsm1;
    wire[31:0]      ownerx= MODULE_ID%2;
    wire            owner = ownerx[0];
    wire            rdReq_valid = fsm1==SEND_RD;
    wire            wrReq_valid = fsm1==SEND_WR;
    
    always @(posedge Clk_32UI)
    begin
            if(!test_Resetb)        
            begin
                    if(owner)       fsm1    <= SEND_WR;
                    else            fsm1    <= SEND_RD;
            end
            else
            begin
                    case(fsm1)
                    SEND_WR: begin           //Next state- WR_PEND
                                    if(req_sent)
                                    begin
                                            fsm1        <= WR_PEND;
                                    end
                            end
                    SEND_RD: begin           // Next state- RD_PEND
                                    if(req_sent)
                                    begin
                                            fsm1        <= RD_PEND;
                                    end
                            end
                    RD_PEND:begin
                                    if(req_cmp)
                                    begin
                                    if(owner) fsm1    <= SEND_WR;
                                    else      fsm1    <= SEND_RD;
                                    end
                            end
                    WR_PEND:begin
                                    if(req_cmp)
                                    fsm1    <= SEND_RD;
                            end
                    endcase
            end
    end
endmodule
