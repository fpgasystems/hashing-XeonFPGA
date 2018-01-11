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
// Module Name:         test_lpbk1.v
// Project:             NLB AFU 
// Description:         memory copy test
//
// ***************************************************************************
// ---------------------------------------------------------------------------------------------------------------------------------------------------
//                                         Loopback 1- memory copy test
//  ------------------------------------------------------------------------------------------------------------------------------------------------
//
// This is a memory copy test. It copies cache lines from source to destination buffer.
//

module test_lpbk1 #(parameter PEND_THRESH=1, ADDR_LMT=20, MDATA=14)
(

//      ---------------------------global signals-------------------------------------------------
       Clk_32UI               ,        // in    std_logic;  -- Core clock
       Resetb                 ,        // in    std_logic;  -- Use SPARINGLY only for control

       l12ab_WrAddr,                   // [ADDR_LMT-1:0]        arb:               write address
       l12ab_WrTID,                    // [ADDR_LMT-1:0]        arb:               meta data
       l12ab_WrDin,                    // [511:0]               arb:               Cache line data
       l12ab_WrEn,                     //                       arb:               write enable
       ab2l1_WrSent,                   //                       arb:               write issued
       ab2l1_WrAlmFull,                //                       arb:               write fifo almost full
       
       l12ab_RdAddr,                   // [ADDR_LMT-1:0]        arb:               Reads may yield to writes
       l12ab_RdTID,                    // [13:0]                arb:               meta data
       l12ab_RdEn,                     //                       arb:               read enable
       ab2l1_RdSent,                   //                       arb:               read issued

       ab2l1_RdRspValid,               //                       arb:               read response valid
       ab2l1_RdRsp,                    // [13:0]                arb:               read response header
       ab2l1_RdRspAddr,                // [ADDR_LMT-1:0]        arb:               read response address
       ab2l1_RdData,                   // [511:0]               arb:               read data
       ab2l1_stallRd,                  //                       arb:               stall read requests FOR LPBK1

       ab2l1_WrRspValid,               //                       arb:               write response valid
       ab2l1_WrRsp,                    // [13:0]                arb:               write response header
       ab2l1_WrRspAddr,                // [ADDR_LMT-1:0]        arb:               write response address
       re2xy_go,                       //                       requestor:         start the test
       re2xy_NumLines,                 // [31:0]                requestor:         number of cache lines
       re2xy_Cont,                     //                       requestor:         continuous mode

       l12ab_TestCmp,                  //                       arb:               Test completion flag
       l12ab_ErrorInfo,                // [255:0]               arb:               error information
       l12ab_ErrorValid,               //                       arb:               test has detected an error
       test_Resetb                     //                       requestor:         rest the app
);
    input                   Clk_32UI;               //                      csi_top:            Clk_32UI
    input                   Resetb;                 //                      csi_top:            system Resetb
    
    output  [ADDR_LMT-1:0]  l12ab_WrAddr;           // [ADDR_LMT-1:0]        arb:               write address
    output  [13:0]          l12ab_WrTID;            // [13:0]                arb:               meta data
    output  [511:0]         l12ab_WrDin;            // [511:0]               arb:               Cache line data
    output                  l12ab_WrEn;             //                       arb:               write enable
    input                   ab2l1_WrSent;           //                       arb:               write issued
    input                   ab2l1_WrAlmFull;        //                       arb:               write fifo almost full
           
    output  [ADDR_LMT-1:0]  l12ab_RdAddr;           // [ADDR_LMT-1:0]        arb:               Reads may yield to writes
    output  [13:0]          l12ab_RdTID;            // [13:0]                arb:               meta data
    output                  l12ab_RdEn;             //                       arb:               read enable
    input                   ab2l1_RdSent;           //                       arb:               read issued
    
    input                   ab2l1_RdRspValid;       //                       arb:               read response valid
    input  [13:0]           ab2l1_RdRsp;            // [13:0]                arb:               read response header
    input  [ADDR_LMT-1:0]   ab2l1_RdRspAddr;        // [ADDR_LMT-1:0]        arb:               read response address
    input  [511:0]          ab2l1_RdData;           // [511:0]               arb:               read data
    input                   ab2l1_stallRd;          //                       arb:               stall read requests FOR LPBK1
    
    input                   ab2l1_WrRspValid;       //                       arb:               write response valid
    input  [13:0]           ab2l1_WrRsp;            // [13:0]                arb:               write response header
    input  [ADDR_LMT-1:0]   ab2l1_WrRspAddr;        // [Addr_LMT-1:0]        arb:               write response address
    
    input                   re2xy_go;               //                       requestor:         start of frame recvd
    input  [31:0]           re2xy_NumLines;         // [31:0]                requestor:         number of cache lines
    input                   re2xy_Cont;             //                       requestor:         continuous mode
    
    output                  l12ab_TestCmp;          //                       arb:               Test completion flag
    output [255:0]          l12ab_ErrorInfo;        // [255:0]               arb:               error information
    output                  l12ab_ErrorValid;       //                       arb:               test has detected an error
    input                   test_Resetb;
    //------------------------------------------------------------------------------------------------------------------------
    
    reg     [ADDR_LMT-1:0]  l12ab_WrAddr;           // [ADDR_LMT-1:0]        arb:               Writes are guaranteed to be accepted
    wire    [13:0]          l12ab_WrTID;            // [13:0]                arb:               meta data
    reg     [511:0]         l12ab_WrDin;            // [511:0]               arb:               Cache line data
    reg                     l12ab_WrEn;             //                       arb:               write enable
    reg     [ADDR_LMT-1:0]  l12ab_RdAddr;           // [ADDR_LMT-1:0]        arb:               Reads may yield to writes
    wire    [13:0]          l12ab_RdTID;            // [13:0]                arb:               meta data
    reg                     l12ab_RdEn;             //                       arb:               read enable
    reg                     l12ab_TestCmp;          //                       arb:               Test completion flag
    reg    [255:0]          l12ab_ErrorInfo;        // [255:0]               arb:               error information
    reg                     l12ab_ErrorValid;       //                       arb:               test has detected an error
    
    reg     [7:0]           rd_mdata;     // limit max mdata to 8 bits or 256 requests
    reg     [2**8-1:0]      rd_mdata_pend;          // bitvector to track used mdata values
    reg     [MDATA-1:0]     wr_mdata;
    reg                     rd_mdata_avail;         // is the next rd madata free and available
    reg     [1:0]           read_fsm;
    reg     [1:0]           write_fsm;
    reg     [31:0]          Num_Reads;
    reg     [31:0]          Num_Writes;
    reg     [31:0]          Num_Pend;
    
    reg     [31:0]          Num_sent;
    reg     [31:0]          Num_rcvd;
    
    assign                  l12ab_WrTID     = 14'h0000| wr_mdata;
    assign                  l12ab_RdTID     = 14'h0000| rd_mdata;
    
    always @(posedge Clk_32UI)
    begin
            //Read FSM
            case(read_fsm)  /* synthesis parallel_case */
            2'h0:   begin                           // Wait for re2xy_go
                            l12ab_RdAddr            <= 0;
                            Num_Reads               <= 0;
                            if(re2xy_go)
                            if(re2xy_NumLines!=0)
                                    read_fsm        <= 2'h1;
                            else    read_fsm        <= 2'h2;
                    end
            2'h1:   begin                           // Send read requests
                            if(ab2l1_RdSent)        
                            begin   
                                    l12ab_RdAddr    <= l12ab_RdAddr + 1'b1;
                                    Num_Reads       <= Num_Reads    + 1'b1;            // final count will be same as re2xy_NumLines
                                   
                                    if(Num_Reads >= re2xy_NumLines-1)
                                    if(re2xy_Cont)    read_fsm        <= 2'h0;
                                    else              read_fsm        <= 2'h2;
                            end // ab2l1_RdSent
                    end
            default:                read_fsm        <= read_fsm;
            endcase
            
            //Write FSM
            case(write_fsm) /* synthesis parallel_case */
            2'h0:   begin
                            if(ab2l1_RdRspValid)
                            begin
                                    l12ab_WrAddr    <= ab2l1_RdRspAddr;
                                    l12ab_WrDin     <= ab2l1_RdData;
                                    write_fsm       <= 2'h1;
                            end
                    end
            2'h1:   begin
                            if(ab2l1_WrSent)                                        // assuming that this will always be set
                            begin
                                    Num_Writes      <= Num_Writes   + 1;            // final count will be same as re2xy_NumLines
    
                                    if(!ab2l1_RdRspValid)
                                            write_fsm       <= 2'h0;
                                    
                                    if(Num_Writes >= re2xy_NumLines-1)
                                    begin
                                            if(!re2xy_Cont)  write_fsm      <= 2'h2;
                                            else             Num_Writes     <= 0;
                                    end
    
                                    if(ab2l1_RdRspValid)
                                    begin
                                            l12ab_WrAddr    <= ab2l1_RdRspAddr;
                                            l12ab_WrDin     <= ab2l1_RdData;
                                    end
                            end
                    end
            default:                write_fsm       <= write_fsm;
            endcase
            
    
            if(l12ab_RdEn && ab2l1_RdSent)
            begin
                    rd_mdata_pend[rd_mdata] <= 1'b1;
                    rd_mdata                <= rd_mdata + 1'b1;
                    rd_mdata_avail  <= !rd_mdata_pend[rd_mdata + 1'b1];
            end
            else
            begin
                    rd_mdata_avail <= !rd_mdata_pend[rd_mdata];
            end
    
            if(ab2l1_RdRspValid)
            begin
                    rd_mdata_pend[ab2l1_RdRsp] <= 1'b0;
            end
    
            if(l12ab_WrEn && ab2l1_WrSent)
                    wr_mdata   <= wr_mdata + 1'b1;
                    
            
            if((l12ab_RdEn && ab2l1_RdSent) && !(l12ab_WrEn && ab2l1_WrSent))      Num_sent        <= Num_sent + 1;
            else if(!(l12ab_RdEn && ab2l1_RdSent) && (l12ab_WrEn && ab2l1_WrSent)) Num_sent        <= Num_sent + 1;
            else if((l12ab_RdEn && ab2l1_RdSent) &&  (l12ab_WrEn && ab2l1_WrSent)) Num_sent        <= Num_sent + 2;
            if((ab2l1_RdRspValid && ab2l1_WrRspValid))                             Num_rcvd        <= Num_rcvd + 2;
            else if((ab2l1_RdRspValid ^ ab2l1_WrRspValid))                         Num_rcvd        <= Num_rcvd + 1;
            
            if(   read_fsm==2'h2
               && write_fsm==2'h2
               && Num_Pend ==0)
                    l12ab_TestCmp <= 1;
    
           
            if(!test_Resetb)
            begin
                    l12ab_WrAddr            <= 0;
    //              l12ab_WrDin             <= 0;
                    l12ab_RdAddr            <= 0;
                    l12ab_TestCmp           <= 0;
                    l12ab_ErrorInfo         <= 0;
                    l12ab_ErrorValid        <= 0;
                    read_fsm                <= 0;
                    write_fsm               <= 0;
                    rd_mdata                <= 0;
                    rd_mdata_avail          <= 1;
                    rd_mdata_pend           <= 0;
                    wr_mdata                <= 0;
                    Num_Reads               <= 0;
                    Num_Writes              <= 0;
                    Num_sent                <= 0;
                    Num_rcvd                <= 0;
            end
            
    end
    
    always @(*)
    begin
            l12ab_RdEn = (read_fsm  ==2'h1) & !ab2l1_stallRd & rd_mdata_avail;
            l12ab_WrEn = (write_fsm ==2'h1);
            Num_Pend   = Num_sent - Num_rcvd;
    end
    
endmodule
