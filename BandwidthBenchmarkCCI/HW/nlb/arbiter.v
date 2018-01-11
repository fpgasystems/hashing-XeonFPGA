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
//
// Engineer:            Pratik Marolia
// Create Date:         Thu Jul 28 20:31:17 PDT 2011
// Module Name:         arbiter.v
// Project:             NLB AFU 
// Description:
//
// ***************************************************************************
//
// ---------------------------------------------------------------------------------------------------------------------------------------------------
//                                         Arbiter
//  ------------------------------------------------------------------------------------------------------------------------------------------------
//
// This module instantiates different test AFUs, and connect them up to the arbiter.

module arbiter #(parameter PEND_THRESH=1, ADDR_LMT=20, MDATA=14)
(

       // ---------------------------global signals-------------------------------------------------
       Clk_32UI               ,        // in    std_logic;  -- Core clock
       Clk_16UI               ,        // in    std_logic;  -- Core clock
       Resetb                 ,        // in    std_logic;  -- Use SPARINGLY only for control

       ab2re_WrAddr,                   // [ADDR_LMT-1:0]        app_cnt:           write address
       ab2re_WrTID,                    // [13:0]                app_cnt:           meta data
       ab2re_WrDin,                    // [511:0]               app_cnt:           Cache line data
       ab2re_WrFence,                  //                       app_cnt:           write fence
       ab2re_WrEn,                     //                       app_cnt:           write enable
       re2ab_WrSent,                   //                       app_cnt:           write issued
       re2ab_WrAlmFull,                //                       app_cnt:           write fifo almost full
       
       ab2re_RdAddr,                   // [ADDR_LMT-1:0]        app_cnt:           Reads may yield to writes
       ab2re_RdTID,                    // [13:0]                app_cnt:           meta data
       ab2re_RdEn,                     //                       app_cnt:           read enable
       re2ab_RdSent,                   //                       app_cnt:           read issued

       re2ab_RdRspValid,               //                       app_cnt:           read response valid
       re2ab_UMsgValid,                //                       arbiter:           UMsg valid
       re2ab_CfgValid,                 //                       arbiter:           Cfg valid
       re2ab_RdRsp,                    // [13:0]                app_cnt:           read response header
       re2ab_RdData,                   // [511:0]               app_cnt:           read data
       re2ab_stallRd,                  //                       app_cnt:           stall read requests FOR LPBK1

       re2ab_WrRspValid,               //                       app_cnt:           write response valid
       re2ab_WrRsp,                    // [ADDR_LMT-1:0]        app_cnt:           write response header
       re2xy_go,                       //                       requestor:         start the test
       re2xy_src_addr,                 // [31:0]                requestor:         src address
       re2xy_dst_addr,                 // [31:0]                requestor:         destination address
       re2xy_NumLines,                 // [31:0]                requestor:         number of cache lines
       re2xy_radix_bits,
       re2xy_dummy_key,
       re2xy_rate_limit,
       re2xy_read_burst_size,
       re2xy_write_burst_size,
       re2xy_Cont,                     //                       requestor:         continuous mode
       re2xy_test_cfg,                 // [7:0]                 requestor:         8-bit test cfg register.
       re2ab_Mode,                     // [2:0]                 requestor:         test mode
       
       ab2re_TestCmp,                  //                       arbiter:           Test completion flag
       ab2re_ErrorInfo,                // [255:0]               arbiter:           error information
       ab2re_ErrorValid,               //                       arbiter:           test has detected an error
       test_Resetb                     //                       requestor:         rest the app
);
   
   input                   Clk_32UI;               //                      csi_top:            Clk_32UI
   input                   Clk_16UI;               //                      csi_top:            Clk_16UI
   input                   Resetb;                 //                      csi_top:            system Resetb
   
   output [ADDR_LMT-1:0]   ab2re_WrAddr;           // [ADDR_LMT-1:0]        app_cnt:           Writes are guaranteed to be accepted
   output [13:0]           ab2re_WrTID;            // [13:0]                app_cnt:           meta data
   output [511:0]          ab2re_WrDin;            // [511:0]               app_cnt:           Cache line data
   output                  ab2re_WrFence;          //                       app_cnt:           write fence.
   output                  ab2re_WrEn;             //                       app_cnt:           write enable
   input                   re2ab_WrSent;           //                       app_cnt:           write issued
   input                   re2ab_WrAlmFull;        //                       app_cnt:           write fifo almost full
   
   output [ADDR_LMT-1:0]   ab2re_RdAddr;           // [ADDR_LMT-1:0]        app_cnt:           Reads may yield to writes
   output [13:0]           ab2re_RdTID;            // [13:0]                app_cnt:           meta data
   output                  ab2re_RdEn;             //                       app_cnt:           read enable
   input                   re2ab_RdSent;           //                       app_cnt:           read issued
   
   input                   re2ab_RdRspValid;       //                       app_cnt:           read response valid
   input                   re2ab_UMsgValid;        //                       arbiter:           UMsg valid
   input                   re2ab_CfgValid;         //                       arbiter:           Cfg valid
   input [13:0]            re2ab_RdRsp;            // [13:0]                app_cnt:           read response header
   input [511:0]           re2ab_RdData;           // [511:0]               app_cnt:           read data
   input                   re2ab_stallRd;          //                       app_cnt:           stall read requests FOR LPBK1
   
   input                   re2ab_WrRspValid;       //                       app_cnt:           write response valid
   input [13:0]            re2ab_WrRsp;            // [13:0]                app_cnt:           write response header
   
   input                   re2xy_go;               //                       requestor:         start of frame recvd
   input [31:0]            re2xy_src_addr;         // [31:0]                requestor:         src address
   input [31:0]            re2xy_dst_addr;         // [31:0]                requestor:         destination address
   input [31:0]            re2xy_NumLines;         // [31:0]                requestor:         number of cache lines
   input [31:0]            re2xy_radix_bits;
   input [31:0]            re2xy_dummy_key;
   input [31:0]            re2xy_rate_limit;
   input [31:0]            re2xy_read_burst_size;
   input [31:0]            re2xy_write_burst_size;
   input                   re2xy_Cont;             //                       requestor:         continuous mode
   input [7:0]             re2xy_test_cfg;         // [7:0]                 requestor:         8-bit test cfg register.
   input [2:0]             re2ab_Mode;             // [2:0]                 requestor:         test mode
   
   output                  ab2re_TestCmp;          //                       arbiter:           Test completion flag
   output [255:0]          ab2re_ErrorInfo;        // [255:0]               arbiter:           error information
   output                  ab2re_ErrorValid;       //                       arbiter:           test has detected an error
   
   input                   test_Resetb;
   //------------------------------------------------------------------------------------------------------------------------
   
   // Test Modes
   //--------------------------------------------------------
   localparam              M_LPBK1         = 3'b000;
   localparam              M_READ          = 3'b001;
   localparam              M_WRITE         = 3'b010;
   localparam              M_TRPUT         = 3'b011;
   localparam              M_LPBK2         = 3'b101;
   localparam              M_LPBK3         = 3'b110;
   localparam              M_SW1           = 3'b111;
   //--------------------------------------------------------

   wire                    Clk_32UI;               //                      csi_top:            Clk_32UI
   wire                    Clk_16UI;               //                      csi_top:            Clk_16UI
   wire                    Resetb;                 //                      csi_top:            system Resetb
   
   reg [ADDR_LMT-1:0]      ab2re_WrAddr;           // [ADDR_LMT-1:0]        app_cnt:           Writes are guaranteed to be accepted
   reg [13:0]              ab2re_WrTID;            // [13:0]                app_cnt:           meta data
   reg [511:0]             ab2re_WrDin;            // [511:0]               app_cnt:           Cache line data
   reg                     ab2re_WrEn;             //                       app_cnt:           write enable
   reg                     ab2re_WrFence;          //
   wire                    re2ab_WrSent;           //                       app_cnt:           write issued
   wire                    re2ab_WrAlmFull;        //                       app_cnt:           write fifo almost full
   
   reg [ADDR_LMT-1:0]      ab2re_RdAddr;           // [ADDR_LMT-1:0]        app_cnt:           Reads may yield to writes
   reg [13:0]              ab2re_RdTID;            // [13:0]                app_cnt:           meta data
   reg                     ab2re_RdEn;             //                       app_cnt:           read enable
   wire                    re2ab_RdSent;           //                       app_cnt:           read issued
   
   wire                    re2ab_RdRspValid;       //                       app_cnt:           read response valid
   wire                    re2ab_UMsgValid;        //                       app_cnt:           UMsg valid
   wire                    re2ab_CfgValid;         //                       app_cnt:           Cfg valid
   wire [13:0]             re2ab_RdRsp;            // [13:0]                app_cnt:           read response header
   wire [511:0]            re2ab_RdData;           // [511:0]               app_cnt:           read data
   wire                    re2ab_stallRd;          //                       app_cnt:           stall read requests FOR LPBK1
   
   wire                    re2ab_WrRspValid;       //                       app_cnt:           write response valid
   wire [13:0]             re2ab_WrRsp;            // [13:0]                app_cnt:           write response header
   
   wire                    re2xy_go;               //                       requestor:         start of frame recvd
   wire [31:0]             re2xy_NumLines;         // [31:0]                requestor:         number of cache lines
   wire [31:0]             re2xy_radix_bits;
   wire [31:0]             re2xy_dummy_key;
   wire [31:0]             re2xy_rate_limit;
   wire [31:0]             re2xy_read_burst_size;
   wire [31:0]             re2xy_write_burst_size;
   wire                    re2xy_Cont;             //                       requestor:         continuous mode
   wire [2:0]              re2ab_Mode;             // [3:0]                 requestor:         test mode
   
   reg                     ab2re_TestCmp;          //                       arbiter:           Test completion flag
   reg [255:0]             ab2re_ErrorInfo;        // [255:0]               arbiter:           error information
   reg                     ab2re_ErrorValid;       //                       arbiter:           test has detected an error
   
   wire                    test_Resetb;

   //------------------------------------------------------------------------------------------------------------------------
   //      test_lpbk1 signal declarations
   //------------------------------------------------------------------------------------------------------------------------
   
   wire [ADDR_LMT-1:0]     l12ab_WrAddr;           // [ADDR_LMT-1:0]        app_cnt:           write address
   wire [13:0]             l12ab_WrTID;            // [13:0]                app_cnt:           meta data
   wire [511:0]            l12ab_WrDin;            // [511:0]               app_cnt:           Cache line data
   wire                    l12ab_WrEn;             //                       app_cnt:           write enable
   reg                     ab2l1_WrSent;           //                       app_cnt:           write issued
   reg                     ab2l1_WrAlmFull;        //                       app_cnt:           write fifo almost full
   
   wire [ADDR_LMT-1:0]     l12ab_RdAddr;           // [ADDR_LMT-1:0]        app_cnt:           Reads may yield to writes
   wire [13:0]             l12ab_RdTID;            // [13:0]                app_cnt:           meta data
   wire                    l12ab_RdEn;             //                       app_cnt:           read enable
   reg                     ab2l1_RdSent;           //                       app_cnt:           read issued
   
   reg                     ab2l1_RdRspValid;       //                       app_cnt:           read response valid
   reg                     ab2l1_UMsgValid;        //                       app_cnt:           UMsg valid
   reg                     ab2l1_CfgValid;         //                       app_cnt:           Cfg valid
   reg [13:0]              ab2l1_RdRsp;            // [13:0]                app_cnt:           read response header
   reg [ADDR_LMT-1:0]      ab2l1_RdRspAddr;        // [ADDR_LMT-1:0]        app_cnt:           read response address
   reg [511:0]             ab2l1_RdData;           // [511:0]               app_cnt:           read data
   reg                     ab2l1_stallRd;          //                       app_cnt:           read stall
   
   reg                     ab2l1_WrRspValid;       //                       app_cnt:           write response valid
   reg [13:0]              ab2l1_WrRsp;            // [13:0]                app_cnt:           write response header
   reg [ADDR_LMT-1:0]      ab2l1_WrRspAddr;        // [Addr_LMT-1:0]        app_cnt:           write response address
   
   wire                    l12ab_TestCmp;          //                       arbiter:           Test completion flag
   wire [255:0]            l12ab_ErrorInfo;        // [255:0]               arbiter:           error information
   wire                    l12ab_ErrorValid;       //                       arbiter:           test has detected an error
   
   //------------------------------------------------------------------------------------------------------------------------
   //      test_rdwr signal declarations
   //------------------------------------------------------------------------------------------------------------------------
   /*
   reg                     ab2rw_RdMode;           //                       arb:               1- reads only test, 0- writes only test
   wire [ADDR_LMT-1:0]     rw2ab_WrAddr;           // [ADDR_LMT-1:0]        app_cnt:           write address
   wire [13:0]             rw2ab_WrTID;            // [13:0]                app_cnt:           meta data
   wire [511:0]            rw2ab_WrDin;            // [511:0]               app_cnt:           Cache line data
   wire                    rw2ab_WrEn;             //                       app_cnt:           write enable
   reg                     ab2rw_WrSent;           //                       app_cnt:           write issued
   reg                     ab2rw_WrAlmFull;        //                       app_cnt:           write fifo almost full
   
   wire [ADDR_LMT-1:0]     rw2ab_RdAddr;           // [ADDR_LMT-1:0]        app_cnt:           Reads may yield to writes
   wire [13:0]             rw2ab_RdTID;            // [13:0]                app_cnt:           meta data
   wire                    rw2ab_RdEn;             //                       app_cnt:           read enable
   reg                     ab2rw_RdSent;           //                       app_cnt:           read issued
   
   reg                     ab2rw_RdRspValid;       //                       app_cnt:           read response valid
   reg [13:0]              ab2rw_RdRsp;            // [13:0]                app_cnt:           read response header
   reg [ADDR_LMT-1:0]      ab2rw_RdRspAddr;        // [ADDR_LMT-1:0]        app_cnt:           read response address
   reg [511:0]             ab2rw_RdData;           // [511:0]               app_cnt:           read data
   
   reg                     ab2rw_WrRspValid;       //                       app_cnt:           write response valid
   reg [13:0]              ab2rw_WrRsp;            // [13:0]                app_cnt:           write response header
   reg [ADDR_LMT-1:0]      ab2rw_WrRspAddr;        // [Addr_LMT-1:0]        app_cnt:           write response address
   
   wire                    rw2ab_TestCmp;          //                       arbiter:           Test completion flag
   wire [255:0]            rw2ab_ErrorInfo;        // [255:0]               arbiter:           error information
   wire                    rw2ab_ErrorValid;       //                       arbiter:           test has detected an error
   */
   //------------------------------------------------------------------------------------------------------------------------
   //      test_thruput signal declarations
   //------------------------------------------------------------------------------------------------------------------------
   
   // reg  [1:0]              ab2rw_Mode;           //                       arb:               1- reads only test, 0- writes only test
   // wire [ADDR_LMT-1:0]     rw2ab_WrAddr;           // [ADDR_LMT-1:0]        app_cnt:           write address
   // wire [13:0]             rw2ab_WrTID;            // [13:0]                app_cnt:           meta data
   // wire [511:0]            rw2ab_WrDin;            // [511:0]               app_cnt:           Cache line data
   // wire                    rw2ab_WrEn;             //                       app_cnt:           write enable
   // reg                     ab2rw_WrSent;           //                       app_cnt:           write issued
   // reg                     ab2rw_WrAlmFull;        //                       app_cnt:           write fifo almost full
   
   // wire [ADDR_LMT-1:0]     rw2ab_RdAddr;           // [ADDR_LMT-1:0]        app_cnt:           Reads may yield to writes
   // wire [13:0]             rw2ab_RdTID;            // [13:0]                app_cnt:           meta data
   // wire                    rw2ab_RdEn;             //                       app_cnt:           read enable
   // reg                     ab2rw_RdSent;           //                       app_cnt:           read issued
   
   // reg                     ab2rw_RdRspValid;       //                       app_cnt:           read response valid
   // reg                     ab2rw_UMsgValid;        //                       app_cnt:           UMsg valid
   // reg                     ab2rw_CfgValid;         //                       app_cnt:           Cfg valid
   // reg [13:0]              ab2rw_RdRsp;            // [13:0]                app_cnt:           read response header
   // reg [ADDR_LMT-1:0]      ab2rw_RdRspAddr;        // [ADDR_LMT-1:0]        app_cnt:           read response address
   // reg [511:0]             ab2rw_RdData;           // [511:0]               app_cnt:           read data
   
   // reg                     ab2rw_WrRspValid;       //                       app_cnt:           write response valid
   // reg [13:0]              ab2rw_WrRsp;            // [13:0]                app_cnt:           write response header
   // reg [ADDR_LMT-1:0]      ab2rw_WrRspAddr;        // [Addr_LMT-1:0]        app_cnt:           write response address
   
   // wire                    rw2ab_TestCmp;          //                       arbiter:           Test completion flag
   // wire [255:0]            rw2ab_ErrorInfo;        // [255:0]               arbiter:           error information
   // wire                    rw2ab_ErrorValid;       //                       arbiter:           test has detected an error
   
   // //------------------------------------------------------------------------------------------------------------------------
   // //      test_lpbk2 signal declarations
   // //------------------------------------------------------------------------------------------------------------------------
   
   // wire [ADDR_LMT-1:0]     l22ab_WrAddr;           // [ADDR_LMT-1:0]        app_cnt:           write address
   // wire [13:0]             l22ab_WrTID;            // [13:0]                app_cnt:           meta data
   // wire [511:0]            l22ab_WrDin;            // [511:0]               app_cnt:           Cache line data
   // wire                    l22ab_WrEn;             //                       app_cnt:           write enable
   // reg                     ab2l2_WrSent;           //                       app_cnt:           write issued
   // reg                     ab2l2_WrAlmFull;        //                       app_cnt:           write fifo almost full
   
   // wire [ADDR_LMT-1:0]     l22ab_RdAddr;           // [ADDR_LMT-1:0]        app_cnt:           Reads may yield to writes
   // wire [13:0]             l22ab_RdTID;            // [13:0]                app_cnt:           meta data
   // wire                    l22ab_RdEn;             //                       app_cnt:           read enable
   // reg                     ab2l2_RdSent;           //                       app_cnt:           read issued
   
   // reg                     ab2l2_RdRspValid;       //                       app_cnt:           read response valid
   // reg                     ab2l2_UMsgValid;        //                       app_cnt:           read response valid
   // reg                     ab2l2_CfgValid;         //                       app_cnt:           read Cfponse valid
   // reg [13:0]              ab2l2_RdRsp;            // [13:0]                app_cnt:           read response header
   // reg [ADDR_LMT-1:0]      ab2l2_RdRspAddr;        // [ADDR_LMT-1:0]        app_cnt:           read response address
   // reg [511:0]             ab2l2_RdData;           // [511:0]               app_cnt:           read data
   
   // reg                     ab2l2_WrRspValid;       //                       app_cnt:           write response valid
   // reg [13:0]              ab2l2_WrRsp;            // [13:0]                app_cnt:           write response header
   // reg [ADDR_LMT-1:0]      ab2l2_WrRspAddr;        // [Addr_LMT-1:0]        app_cnt:           write response address
   
   // wire                    l22ab_TestCmp;          //                       arbiter:           Test completion flag
   // wire [255:0]            l22ab_ErrorInfo;        // [255:0]               arbiter:           error information
   // wire                    l22ab_ErrorValid;       //                       arbiter:           test has detected an error
   
   // //------------------------------------------------------------------------------------------------------------------------
   // //      test_lpbk3 signal declarations
   // //------------------------------------------------------------------------------------------------------------------------
   
   // wire [ADDR_LMT-1:0]     l32ab_WrAddr;           // [ADDR_LMT-1:0]        app_cnt:           write address
   // wire [13:0]             l32ab_WrTID;            // [13:0]                app_cnt:           meta data
   // wire [511:0]            l32ab_WrDin;            // [511:0]               app_cnt:           Cache line data
   // wire                    l32ab_WrEn;             //                       app_cnt:           write enable
   // reg                     ab2l3_WrSent;           //                       app_cnt:           write issued
   // reg                     ab2l3_WrAlmFull;        //                       app_cnt:           write fifo almost full
   
   // wire [ADDR_LMT-1:0]     l32ab_RdAddr;           // [ADDR_LMT-1:0]        app_cnt:           Reads may yield to writes
   // wire [13:0]             l32ab_RdTID;            // [13:0]                app_cnt:           meta data
   // wire                    l32ab_RdEn;             //                       app_cnt:           read enable
   // reg                     ab2l3_RdSent;           //                       app_cnt:           read issued
   
   // reg                     ab2l3_RdRspValid;       //                       app_cnt:           read response valid
   // reg                     ab2l3_UMsgValid;        //                       app_cnt:           UMsg valid
   // reg                     ab2l3_CfgValid;         //                       app_cnt:           read Cfponse valid
   // reg [13:0]              ab2l3_RdRsp;            // [13:0]                app_cnt:           read response header
   // reg [ADDR_LMT-1:0]      ab2l3_RdRspAddr;        // [ADDR_LMT-1:0]        app_cnt:           read response address
   // reg [511:0]             ab2l3_RdData;           // [511:0]               app_cnt:           read data
   
   // reg                     ab2l3_WrRspValid;       //                       app_cnt:           write response valid
   // reg [13:0]              ab2l3_WrRsp;            // [13:0]                app_cnt:           write response header
   // reg [ADDR_LMT-1:0]      ab2l3_WrRspAddr;        // [Addr_LMT-1:0]        app_cnt:           write response address
   
   // wire                    l32ab_TestCmp;          //                       arbiter:           Test completion flag
   // wire [255:0]            l32ab_ErrorInfo;        // [255:0]               arbiter:           error information
   // wire                    l32ab_ErrorValid;       //                       arbiter:           test has detected an error
   
   // //------------------------------------------------------------------------------------------------------------------------
   // //      test_sw1 signal declarations
   // //------------------------------------------------------------------------------------------------------------------------
   
   // wire [ADDR_LMT-1:0]     s12ab_WrAddr;           // [ADDR_LMT-1:0]        app_cnt:           write address
   // wire [13:0]             s12ab_WrTID;            // [13:0]                app_cnt:           meta data
   // wire [511:0]            s12ab_WrDin;            // [511:0]               app_cnt:           Cache line data
   // wire                    s12ab_WrEn;             //                       app_cnt:           write enable
   // wire                    s12ab_WrFence;          //                       app_cnt:           write fence 
   // reg                     ab2s1_WrSent;           //                       app_cnt:           write issued
   // reg                     ab2s1_WrAlmFull;        //                       app_cnt:           write fifo almost full
   
   // wire [ADDR_LMT-1:0]     s12ab_RdAddr;           // [ADDR_LMT-1:0]        app_cnt:           Reads may yield to writes
   // wire [13:0]             s12ab_RdTID;            // [13:0]                app_cnt:           meta data
   // wire                    s12ab_RdEn;             //                       app_cnt:           read enable
   // reg                     ab2s1_RdSent;           //                       app_cnt:           read issued
   
   // reg                     ab2s1_RdRspValid;       //                       app_cnt:           read response valid
   // reg                     ab2s1_UMsgValid;        //                       app_cnt:           UMsg valid
   // reg                     ab2s1_CfgValid;         //                       app_cnt:           Cfg valid
   // reg [13:0]              ab2s1_RdRsp;            // [13:0]                app_cnt:           read response header
   // reg [ADDR_LMT-1:0]      ab2s1_RdRspAddr;        // [ADDR_LMT-1:0]        app_cnt:           read response address
   // reg [511:0]             ab2s1_RdData;           // [511:0]               app_cnt:           read data
   
   // reg                     ab2s1_WrRspValid;       //                       app_cnt:           write response valid
   // reg [13:0]              ab2s1_WrRsp;            // [13:0]                app_cnt:           write response header
   // reg [ADDR_LMT-1:0]      ab2s1_WrRspAddr;        // [Addr_LMT-1:0]        app_cnt:           write response address
   
   // wire                    s12ab_TestCmp;          //                       arbiter:           Test completion flag
   // wire [255:0]            s12ab_ErrorInfo;        // [255:0]               arbiter:           error information
   // wire                    s12ab_ErrorValid;       //                       arbiter:           test has detected an error
   
   //------------------------------------------------------------------------------------------------------------------------

   // local variables
   reg                     re2ab_RdRspValid_q;
   reg                     re2ab_WrRspValid_q;
   reg                     re2ab_UMsgValid_q;
   reg                     re2ab_CfgValid_q; 
   reg [13:0]              re2ab_RdRsp_q;
   reg [13:0]              re2ab_WrRsp_q;
   reg [511:0]             re2ab_RdData_q;
   
   //------------------------------------------------------------------------------------------------------------------------
   // Arbitrataion Memory instantiation
   //------------------------------------------------------------------------------------------------------------------------
   wire [ADDR_LMT-1:0]     arbmem_rd_dout;
   wire [ADDR_LMT-1:0]     arbmem_wr_dout;
   
   nlb_gram_sdp #(.BUS_SIZE_ADDR(MDATA),
              .BUS_SIZE_DATA(ADDR_LMT),
              .GRAM_MODE(2'd1)
              )arb_rd_mem 
            (
                .clk  (Clk_32UI),
                .we   (ab2re_RdEn),        
                .waddr(ab2re_RdTID[MDATA-1:0]),     
                .din  (ab2re_RdAddr),       
                .raddr(re2ab_RdRsp[MDATA-1:0]),     
                .dout (arbmem_rd_dout )
            );     
   
   nlb_gram_sdp #(.BUS_SIZE_ADDR(MDATA),
              .BUS_SIZE_DATA(ADDR_LMT),
              .GRAM_MODE(2'd1)
             )arb_wr_mem 
            (
                .clk  (Clk_32UI),
                .we   (ab2re_WrEn),        
                .waddr(ab2re_WrTID[MDATA-1:0]),     
                .din  (ab2re_WrAddr),       
                .raddr(re2ab_WrRsp[MDATA-1:0]),     
                .dout (arbmem_wr_dout )
            );     
   
   //------------------------------------------------------------------------------------------------------------------------
   always @(posedge Clk_32UI)
     begin
        if(~test_Resetb)
          begin
             re2ab_RdRspValid_q      <= 0;
             re2ab_UMsgValid_q       <= 0;
             re2ab_CfgValid_q        <= 0;
             re2ab_RdRsp_q           <= 0;
             re2ab_RdData_q          <= 0;
             re2ab_WrRspValid_q      <= 0;
             re2ab_WrRsp_q           <= 0;
          end
        else
          begin
             re2ab_RdRspValid_q      <= re2ab_RdRspValid;
             re2ab_UMsgValid_q       <= re2ab_UMsgValid;
             re2ab_CfgValid_q        <= re2ab_CfgValid;
             re2ab_RdRsp_q           <= re2ab_RdRsp;
             re2ab_RdData_q          <= re2ab_RdData;
             re2ab_WrRspValid_q      <= re2ab_WrRspValid;
             re2ab_WrRsp_q           <= re2ab_WrRsp;
          end
     end
   
   always @(*)
     begin
        // OUTPUTs
        ab2re_WrAddr    = 0;
        ab2re_WrTID     = 0;
        ab2re_WrDin     = 'hx;
        ab2re_WrFence   = 0;
        ab2re_WrEn      = 0;
        ab2re_RdAddr    = 0;
        ab2re_RdTID     = 0;
        ab2re_RdEn      = 0;
        ab2re_TestCmp   = 0;
        ab2re_ErrorInfo = 'hx;
        ab2re_ErrorValid= 0;

        // M_LPBK1
        ab2l1_WrSent    = 0;
        ab2l1_WrAlmFull = 0;
        ab2l1_RdSent    = 0;
        ab2l1_RdRspValid= 0;
        ab2l1_RdRsp     = 0;
        ab2l1_RdRspAddr = 0;
        ab2l1_RdData    = 'hx;
        ab2l1_stallRd   = 0;
        ab2l1_WrRspValid= 0;
        ab2l1_WrRsp     = 0;
        ab2l1_WrRspAddr = 0;

        // // M_TRPUT
        // ab2rw_Mode      = 0;
        // ab2rw_WrSent    = 0;
        // ab2rw_WrAlmFull = 0;
        // ab2rw_RdSent    = 0;
        // ab2rw_RdRspValid= 0;
        // ab2rw_RdRsp     = 0;
        // ab2rw_RdRspAddr = 0;
        // ab2rw_RdData    = 'hx;
        // ab2rw_WrRspValid= 0;
        // ab2rw_WrRsp     = 0;
        // ab2rw_WrRspAddr = 0;

        // // M_LPBK2
        // ab2l2_WrSent    = 0;
        // ab2l2_WrAlmFull = 0;
        // ab2l2_RdSent    = 0;
        // ab2l2_RdRspValid= 0;
        // ab2l2_RdRsp     = 0;
        // ab2l2_RdRspAddr = 0;
        // ab2l2_RdData    = 'hx;
        // ab2l2_WrRspValid= 0;
        // ab2l2_WrRsp     = 0;
        // ab2l2_WrRspAddr = 0;

        // // M_LPBK3
        // ab2l3_WrSent    = 0;
        // ab2l3_WrAlmFull = 0;
        // ab2l3_RdSent    = 0;
        // ab2l3_RdRspValid= 0;
        // ab2l3_RdRsp     = 0;
        // ab2l3_RdRspAddr = 0;
        // ab2l3_RdData    = 'hx;
        // ab2l3_WrRspValid= 0;
        // ab2l3_WrRsp     = 0;
        // ab2l3_WrRspAddr = 0;

        // // M_SW1
        // ab2s1_WrSent    = 0;
        // ab2s1_WrAlmFull = 0;
        // ab2s1_RdSent    = 0;
        // ab2s1_RdRspValid= 0;
        // ab2s1_CfgValid  = 0;
        // ab2s1_UMsgValid = 0;
        // ab2s1_RdRsp     = 0;
        // ab2s1_RdRspAddr = 0;
        // ab2s1_RdData    = 'hx;
        // ab2s1_WrRspValid= 0;
        // ab2s1_WrRsp     = 0;
        // ab2s1_WrRspAddr = 0;

        // ---------------------------------------------------------------------------------------------------------------------
        //      Input to tests        
        // ---------------------------------------------------------------------------------------------------------------------
        if(re2ab_Mode==M_LPBK1)
          begin
             ab2l1_WrSent       = re2ab_WrSent;
             ab2l1_WrAlmFull    = re2ab_WrAlmFull;
             ab2l1_RdSent       = re2ab_RdSent;
             ab2l1_RdRspValid   = re2ab_RdRspValid_q;
             ab2l1_UMsgValid    = re2ab_UMsgValid_q;
             ab2l1_CfgValid     = re2ab_CfgValid_q;
             ab2l1_RdRsp        = re2ab_RdRsp_q;
             ab2l1_RdRspAddr    = arbmem_rd_dout;
             ab2l1_RdData       = re2ab_RdData_q;
             ab2l1_stallRd      = re2ab_stallRd;
             ab2l1_WrRspValid   = re2ab_WrRspValid_q;
             ab2l1_WrRsp        = re2ab_WrRsp_q;
             ab2l1_WrRspAddr    = arbmem_wr_dout;
          end

        //  if(re2ab_Mode==M_TRPUT || re2ab_Mode==M_READ || re2ab_Mode==M_WRITE)
        //   begin
        //      ab2rw_Mode         = re2ab_Mode[1:0];
        //      ab2rw_WrSent       = re2ab_WrSent;
        //      ab2rw_WrAlmFull    = re2ab_WrAlmFull;
        //      ab2rw_RdSent       = re2ab_RdSent;
        //      ab2rw_RdRspValid   = re2ab_RdRspValid_q;
        //      ab2rw_UMsgValid    = re2ab_UMsgValid_q;
        //      ab2rw_CfgValid     = re2ab_CfgValid_q;
        //      ab2rw_RdRsp        = re2ab_RdRsp_q;
        //      ab2rw_RdRspAddr    = arbmem_rd_dout;
        //      ab2rw_RdData       = re2ab_RdData_q;
        //      ab2rw_WrRspValid   = re2ab_WrRspValid_q;
        //      ab2rw_WrRsp        = re2ab_WrRsp_q;
        //      ab2rw_WrRspAddr    = arbmem_wr_dout;        
        //   end
        
        // if(re2ab_Mode==M_LPBK2)
        //   begin
        //      ab2l2_WrSent       = re2ab_WrSent;
        //      ab2l2_WrAlmFull    = re2ab_WrAlmFull;
        //      ab2l2_RdSent       = re2ab_RdSent;
        //      ab2l2_RdRspValid   = re2ab_RdRspValid_q;
        //      ab2l2_UMsgValid    = re2ab_UMsgValid_q;
        //      ab2l2_CfgValid     = re2ab_CfgValid_q;
        //      ab2l2_RdRsp        = re2ab_RdRsp_q;
        //      ab2l2_RdRspAddr    = arbmem_rd_dout;
        //      ab2l2_RdData       = re2ab_RdData_q;
        //      ab2l2_WrRspValid   = re2ab_WrRspValid_q;
        //      ab2l2_WrRsp        = re2ab_WrRsp_q;
        //      ab2l2_WrRspAddr    = arbmem_wr_dout;
        //   end
        
        // if(re2ab_Mode==M_LPBK3)
        //   begin
        //      ab2l3_WrSent       = re2ab_WrSent;
        //      ab2l3_WrAlmFull    = re2ab_WrAlmFull;
        //      ab2l3_RdSent       = re2ab_RdSent;
        //      ab2l3_RdRspValid   = re2ab_RdRspValid_q;
        //      ab2l3_UMsgValid    = re2ab_UMsgValid_q;
        //      ab2l3_CfgValid     = re2ab_CfgValid_q;
        //      ab2l3_RdRsp        = re2ab_RdRsp_q;
        //      ab2l3_RdRspAddr    = arbmem_rd_dout;
        //      ab2l3_RdData       = re2ab_RdData_q;
        //      ab2l3_WrRspValid   = re2ab_WrRspValid_q;
        //      ab2l3_WrRsp        = re2ab_WrRsp_q;
        //      ab2l3_WrRspAddr    = arbmem_wr_dout;
        //   end

        // if(re2ab_Mode==M_SW1)
        //   begin
        //      ab2s1_WrSent       = re2ab_WrSent;
        //      ab2s1_WrAlmFull    = re2ab_WrAlmFull;
        //      ab2s1_RdSent       = re2ab_RdSent;
        //      ab2s1_RdRspValid   = re2ab_RdRspValid_q;
        //      ab2s1_UMsgValid    = re2ab_UMsgValid_q;
        //      ab2s1_CfgValid     = re2ab_CfgValid_q;
        //      ab2s1_RdRsp        = re2ab_RdRsp_q;
        //      ab2s1_RdRspAddr    = arbmem_rd_dout;
        //      ab2s1_RdData       = re2ab_RdData_q;
        //      ab2s1_WrRspValid   = re2ab_WrRspValid_q;
        //      ab2s1_WrRsp        = re2ab_WrRsp_q;
        //      ab2s1_WrRspAddr    = arbmem_wr_dout;
        //   end
        
        // ----------------------------------------------------------------------------------------------------------------------
        // Output from tests
        // ----------------------------------------------------------------------------------------------------------------------
        if(re2ab_Mode==M_LPBK1)
          begin
             ab2re_WrAddr       = l12ab_WrAddr;
             ab2re_WrTID        = l12ab_WrTID;
             ab2re_WrDin        = l12ab_WrDin;
             ab2re_WrFence      = 1'b0;
             ab2re_WrEn         = l12ab_WrEn;
             ab2re_RdAddr       = l12ab_RdAddr;
             ab2re_RdTID        = l12ab_RdTID;
             ab2re_RdEn         = l12ab_RdEn;
             ab2re_TestCmp      = l12ab_TestCmp;
             ab2re_ErrorInfo    = l12ab_ErrorInfo;
             ab2re_ErrorValid   = l12ab_ErrorValid;
          end

        // if(re2ab_Mode==M_TRPUT || re2ab_Mode==M_READ || re2ab_Mode==M_WRITE)
        //   begin
        //      ab2re_WrAddr       = rw2ab_WrAddr;
        //      ab2re_WrTID        = rw2ab_WrTID;
        //      ab2re_WrDin        = rw2ab_WrDin;
        //      ab2re_WrFence      = 1'b0;
        //      ab2re_WrEn         = rw2ab_WrEn;
        //      ab2re_RdAddr       = rw2ab_RdAddr;
        //      ab2re_RdTID        = rw2ab_RdTID;
        //      ab2re_RdEn         = rw2ab_RdEn;
        //      ab2re_TestCmp      = rw2ab_TestCmp;
        //      ab2re_ErrorInfo    = rw2ab_ErrorInfo;
        //      ab2re_ErrorValid   = rw2ab_ErrorValid;
        //   end

        // if(re2ab_Mode==M_LPBK2)
        //   begin
        //      ab2re_WrAddr       = l22ab_WrAddr;
        //      ab2re_WrTID        = l22ab_WrTID;
        //      ab2re_WrDin        = l22ab_WrDin;
        //      ab2re_WrFence      = 1'b0;
        //      ab2re_WrEn         = l22ab_WrEn;
        //      ab2re_RdAddr       = l22ab_RdAddr;
        //      ab2re_RdTID        = l22ab_RdTID;
        //      ab2re_RdEn         = l22ab_RdEn;
        //      ab2re_TestCmp      = l22ab_TestCmp;
        //      ab2re_ErrorInfo    = l22ab_ErrorInfo;
        //      ab2re_ErrorValid   = l22ab_ErrorValid;
        //   end
        
        // if(re2ab_Mode==M_LPBK3)
        //   begin
        //      ab2re_WrAddr       = l32ab_WrAddr;
        //      ab2re_WrTID        = l32ab_WrTID;
        //      ab2re_WrDin        = l32ab_WrDin;
        //      ab2re_WrFence      = 1'b0;
        //      ab2re_WrEn         = l32ab_WrEn;
        //      ab2re_RdAddr       = l32ab_RdAddr;
        //      ab2re_RdTID        = l32ab_RdTID;
        //      ab2re_RdEn         = l32ab_RdEn;
        //      ab2re_TestCmp      = l32ab_TestCmp;
        //      ab2re_ErrorInfo    = l32ab_ErrorInfo;
        //      ab2re_ErrorValid   = l32ab_ErrorValid;
        //   end

        // if(re2ab_Mode==M_SW1)
        //   begin
        //      ab2re_WrAddr       = s12ab_WrAddr;
        //      ab2re_WrTID        = s12ab_WrTID;
        //      ab2re_WrDin        = s12ab_WrDin;
        //      ab2re_WrFence      = s12ab_WrFence;
        //      ab2re_WrEn         = s12ab_WrEn;
        //      ab2re_RdAddr       = s12ab_RdAddr;
        //      ab2re_RdTID        = s12ab_RdTID;
        //      ab2re_RdEn         = s12ab_RdEn;
        //      ab2re_TestCmp      = s12ab_TestCmp;
        //      ab2re_ErrorInfo    = s12ab_ErrorInfo;
        //      ab2re_ErrorValid   = s12ab_ErrorValid;
        //   end

     end

    partitioner3 #(.PEND_THRESH  (PEND_THRESH),
                 .ADDR_LMT      (ADDR_LMT),
                 .MDATA         (MDATA),
                 .MAX_RADIX_BITS    (13)
                 )
    partitioner3(
           Clk_32UI               ,        // in    std_logic;  -- Core clock
           Clk_16UI               ,        // in    std_logic;  -- Core clock
           Resetb                 ,        // in    std_logic;  -- Use SPARINGLY only for control
    
           l12ab_WrAddr,                   // [ADDR_LMT-1:0]        app_cnt:           write address
           l12ab_WrTID,                    // [ADDR_LMT-1:0]        app_cnt:           meta data
           l12ab_WrDin,                    // [511:0]               app_cnt:           Cache line data
           l12ab_WrEn,                     //                       app_cnt:           write enable
           ab2l1_WrSent,                   //                       app_cnt:           write issued
           ab2l1_WrAlmFull,                //                       app_cnt:           write fifo almost full
           
           l12ab_RdAddr,                   // [ADDR_LMT-1:0]        app_cnt:           Reads may yield to writes
           l12ab_RdTID,                    // [13:0]                app_cnt:           meta data
           l12ab_RdEn,                     //                       app_cnt:           read enable
           ab2l1_RdSent,                   //                       app_cnt:           read issued
    
           ab2l1_RdRspValid,               //                       app_cnt:           read response valid
           ab2l1_RdRsp,                    // [13:0]                app_cnt:           read response header
           ab2l1_RdRspAddr,                // [ADDR_LMT-1:0]        app_cnt:           read response address
           ab2l1_RdData,                   // [511:0]               app_cnt:           read data
           ab2l1_stallRd,                  //                       app_cnt:           stall read requests FOR LPBK1
    
           ab2l1_WrRspValid,               //                       app_cnt:           write response valid
           ab2l1_WrRsp,                    // [13:0]                app_cnt:           write response header
           ab2l1_WrRspAddr,                // [ADDR_LMT-1:0]        app_cnt:           write response address
           re2xy_go,                       //                       requestor:         start the test
           re2xy_NumLines,                 // [31:0]                requestor:         number of cache lines
           re2xy_radix_bits,
           re2xy_dummy_key,
           re2xy_rate_limit,
           re2xy_read_burst_size,
           re2xy_write_burst_size,
           re2xy_Cont,                     //                       requestor:         continuous mode
    
           l12ab_TestCmp,                  //                       arbiter:           Test completion flag
           l12ab_ErrorInfo,                // [255:0]               arbiter:           error information
           l12ab_ErrorValid,               //                       arbiter:           test has detected an error
           test_Resetb                     //                       requestor:         rest the app
    );
    
    // test_rdwr #(.PEND_THRESH(PEND_THRESH),
    //             .ADDR_LMT   (ADDR_LMT),
    //             .MDATA      (MDATA)
    //             )
    
    // test_rdwr(
    
    // //      ---------------------------global signals-------------------------------------------------
    //        Clk_32UI               ,        // in    std_logic;  -- Core clock
    //        Resetb                 ,        // in    std_logic;  -- Use SPARINGLY only for control
    //        ab2rw_Mode           ,        //                       arb:               1- reads only test, 0- writes only test
    
    //        rw2ab_WrAddr,                   // [ADDR_LMT-1:0]        arb:               write address
    //        rw2ab_WrTID,                    // [ADDR_LMT-1:0]        arb:               meta data
    //        rw2ab_WrDin,                    // [511:0]               arb:               Cache line data
    //        rw2ab_WrEn,                     //                       arb:               write enable
    //        ab2rw_WrSent,                   //                       arb:               write issued
    //        ab2rw_WrAlmFull,                //                       arb:               write fifo almost full
           
    //        rw2ab_RdAddr,                   // [ADDR_LMT-1:0]        arb:               Reads may yield to writes
    //        rw2ab_RdTID,                    // [13:0]                arb:               meta data
    //        rw2ab_RdEn,                     //                       arb:               read enable
    //        ab2rw_RdSent,                   //                       arb:               read issued
    
    //        ab2rw_RdRspValid,               //                       arb:               read response valid
    //        ab2rw_RdRsp,                    // [13:0]                arb:               read response header
    //        ab2rw_RdRspAddr,                // [ADDR_LMT-1:0]        arb:               read response address
    //        ab2rw_RdData,                   // [511:0]               arb:               read data
    
    //        ab2rw_WrRspValid,               //                       arb:               write response valid
    //        ab2rw_WrRsp,                    // [13:0]                arb:               write response header
    //        ab2rw_WrRspAddr,                // [ADDR_LMT-1:0]        arb:               write response address
    //        re2xy_go,                       //                       requestor:         start the test
    //        re2xy_NumLines,                 // [31:0]                requestor:         number of cache lines
    //        re2xy_Cont,                     //                       requestor:         continuous mode
    
    //        rw2ab_TestCmp,                  //                       arb:               Test completion flag
    //        rw2ab_ErrorInfo,                // [255:0]               arb:               error information
    //        rw2ab_ErrorValid,               //                       arb:               test has detected an error
    //        test_Resetb                     //                       requestor:         rest the app
    // );
    
    // test_lpbk2 #(.PEND_THRESH(PEND_THRESH),
    //              .ADDR_LMT   (ADDR_LMT   ),
    //              .MDATA      (MDATA)
    //              )
    // test_lpbk2(
    
    // //      ---------------------------global signals-------------------------------------------------
    //        Clk_32UI               ,        // in    std_logic;  -- Core clock
    //        Resetb                 ,        // in    std_logic;  -- Use SPARINGLY only for control
    
    //        l22ab_WrAddr,                   // [ADDR_LMT-1:0]        arb:               write address
    //        l22ab_WrTID,                    // [ADDR_LMT-1:0]        arb:               meta data
    //        l22ab_WrDin,                    // [511:0]               arb:               Cache line data
    //        l22ab_WrEn,                     //                       arb:               write enable
    //        ab2l2_WrSent,                   //                       arb:               write issued
    //        ab2l2_WrAlmFull,                //                       arb:               write fifo almost full
           
    //        l22ab_RdAddr,                   // [ADDR_LMT-1:0]        arb:               Reads may yield to writes
    //        l22ab_RdTID,                    // [13:0]                arb:               meta data
    //        l22ab_RdEn,                     //                       arb:               read enable
    //        ab2l2_RdSent,                   //                       arb:               read issued
    
    //        ab2l2_RdRspValid,               //                       arb:               read response valid
    //        ab2l2_RdRsp,                    // [13:0]                arb:               read response header
    //        ab2l2_RdRspAddr,                // [ADDR_LMT-1:0]        arb:               read response address
    //        ab2l2_RdData,                   // [511:0]               arb:               read data
    
    //        ab2l2_WrRspValid,               //                       arb:               write response valid
    //        ab2l2_WrRsp,                    // [13:0]                arb:               write response header
    //        ab2l2_WrRspAddr,                // [ADDR_LMT-1:0]        arb:               write response address
    //        re2xy_go,                       //                       requestor:         start the test
    //        re2xy_src_addr,                 // [31:0]                requestor:         src address
    //        re2xy_dst_addr,                 // [31:0]                requestor:         destination address
    //        re2xy_NumLines,                 // [31:0]                requestor:         number of cache lines
    //        re2xy_Cont,                     //                       requestor:         continuous mode
    
    //        l22ab_TestCmp,                  //                       arb:               Test completion flag
    //        l22ab_ErrorInfo,                // [255:0]               arb:               error information
    //        l22ab_ErrorValid,               //                       arb:               test has detected an error
    //        test_Resetb                     //                       requestor:         rest the app
    // );
    
    // test_lpbk3 #(.PEND_THRESH(PEND_THRESH),
    //              .ADDR_LMT   (ADDR_LMT   ),
    //              .MDATA      (MDATA      )
    //              )
    // test_lpbk3(
    
    // //      ---------------------------global signals-------------------------------------------------
    //        Clk_32UI               ,        // in    std_logic;  -- Core clock
    //        Resetb                 ,        // in    std_logic;  -- Use SPARINGLY only for control
    
    //        l32ab_WrAddr,                   // [ADDR_LMT-1:0]        arb:               write address
    //        l32ab_WrTID,                    // [ADDR_LMT-1:0]        arb:               meta data
    //        l32ab_WrDin,                    // [511:0]               arb:               Cache line data
    //        l32ab_WrEn,                     //                       arb:               write enable
    //        ab2l3_WrSent,                   //                       arb:               write issued
    //        ab2l3_WrAlmFull,                //                       arb:               write fifo almost full
           
    //        l32ab_RdAddr,                   // [ADDR_LMT-1:0]        arb:               Reads may yield to writes
    //        l32ab_RdTID,                    // [13:0]                arb:               meta data
    //        l32ab_RdEn,                     //                       arb:               read enable
    //        ab2l3_RdSent,                   //                       arb:               read issued
    
    //        ab2l3_RdRspValid,               //                       arb:               read response valid
    //        ab2l3_RdRsp,                    // [13:0]                arb:               read response header
    //        ab2l3_RdRspAddr,                // [ADDR_LMT-1:0]        arb:               read response address
    //        ab2l3_RdData,                   // [511:0]               arb:               read data
    
    //        ab2l3_WrRspValid,               //                       arb:               write response valid
    //        ab2l3_WrRsp,                    // [13:0]                arb:               write response header
    //        ab2l3_WrRspAddr,                // [ADDR_LMT-1:0]        arb:               write response address
    //        re2xy_go,                       //                       requestor:         start the test
    //        re2xy_src_addr,                 // [31:0]                requestor:         src address
    //        re2xy_dst_addr,                 // [31:0]                requestor:         destination address
    //        re2xy_NumLines,                 // [31:0]                requestor:         number of cache lines
    //        re2xy_Cont,                     //                       requestor:         continuous mode
    
    //        l32ab_TestCmp,                  //                       arb:               Test completion flag
    //        l32ab_ErrorInfo,                // [255:0]               arb:               error information
    //        l32ab_ErrorValid,               //                       arb:               test has detected an error
    //        test_Resetb                     //                       requestor:         rest the app
    // );
    
    // test_sw1  #(.PEND_THRESH(PEND_THRESH),
    //             .ADDR_LMT   (ADDR_LMT),
    //             .MDATA      (MDATA)
    //             )
    
    // test_sw1 (
    
    // //      ---------------------------global signals-------------------------------------------------
    //        Clk_32UI               ,        // in    std_logic;  -- Core clock
    //        Resetb                 ,        // in    std_logic;  -- Use SPARINGLY only for control
    
    //        s12ab_WrAddr,                   // [ADDR_LMT-1:0]        arb:               write address
    //        s12ab_WrTID,                    // [ADDR_LMT-1:0]        arb:               meta data
    //        s12ab_WrDin,                    // [511:0]               arb:               Cache line data
    //        s12ab_WrFence,                  //                       arb:               write fence 
    //        s12ab_WrEn,                     //                       arb:               write enable
    //        ab2s1_WrSent,                   //                       arb:               write issued
    //        ab2s1_WrAlmFull,                //                       arb:               write fifo almost full
           
    //        s12ab_RdAddr,                   // [ADDR_LMT-1:0]        arb:               Reads may yield to writes
    //        s12ab_RdTID,                    // [13:0]                arb:               meta data
    //        s12ab_RdEn,                     //                       arb:               read enable
    //        ab2s1_RdSent,                   //                       arb:               read issued
    
    //        ab2s1_RdRspValid,               //                       arb:               read response valid
    //        ab2s1_UMsgValid,                //                       arb:               UMsg valid
    //        ab2s1_CfgValid,                 //                       arb:               Cfg valid
    //        ab2s1_RdRsp,                    // [13:0]                arb:               read response header
    //        ab2s1_RdRspAddr,                // [ADDR_LMT-1:0]        arb:               read response address
    //        ab2s1_RdData,                   // [511:0]               arb:               read data
    
    //        ab2s1_WrRspValid,               //                       arb:               write response valid
    //        ab2s1_WrRsp,                    // [13:0]                arb:               write response header
    //        ab2s1_WrRspAddr,                // [ADDR_LMT-1:0]        arb:               write response address
    //        re2xy_go,                       //                       requestor:         start the test
    //        re2xy_NumLines,                 // [31:0]                requestor:         number of cache lines
    //        re2xy_Cont,                     //                       requestor:         continuous mode
    //        re2xy_test_cfg,                 // [7:0]                 requestor:         8-bit test cfg register.
    
    //        s12ab_TestCmp,                  //                       arb:               Test completion flag
    //        s12ab_ErrorInfo,                // [255:0]               arb:               error information
    //        s12ab_ErrorValid,               //                       arb:               test has detected an error
    //        test_Resetb                     //                       requestor:         rest the app
    // );

endmodule
