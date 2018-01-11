// ***************************************************************************
// Copyright (C) 2008-2015 Intel Corporation All Rights Reserved.
// The source code contained or described herein and all  documents related to
// the  source  code  ("Material")  are  owned  by  Intel  Corporation  or its
// suppliers  or  licensors.    Title  to  the  Material  remains  with  Intel
// Corporation or  its suppliers  and licensors.  The Material  contains trade
// secrets  and  proprietary  and  confidential  information  of  Intel or its
// suppliers and licensors.  The Material is protected  by worldwide copyright
// and trade secret laws and treaty provisions. No part of the Material may be
// used,   copied,   reproduced,   modified,   published,   uploaded,  posted,
// transmitted,  distributed,  or  disclosed  in any way without Intel's prior
// express written permission.
//
//
// ome_top.sv:
// Arthur.Sheiman@Intel.com: Created 01-31-10
// Revised 11-29-13  18:57

// This wraps one_bot.sv, which is more readable. Might want to look there
// if don't need the signal attributes.
//
// Top level module for HW Home Agent accelerator project.
// Project "ome" for native loopback:
//   qph: PHY, physical layer
//   qlp: LP, link/protocol layer
//   mc: Memory controller
//   nlb: Native loopback
//
// Multiple top level projects are possible. the ../top/qph_top.sv is
// a symbolic link that points to a HW top level project file, such
// as this one.



module ome_top(
  // Reset and clocks
(* altera_attribute = "-name IO_STANDARD \"2.5-V\"" *)  input                     pin_cmos25_inp_vl_QPI_PWRGOOD,                    // Actually a master reset that can be retriggered
(* altera_attribute = "-name IO_STANDARD \"2.5-V\"" *)  input                     pin_cmos25_inp_vl_HSECLK_112,                     // CMOS 112.5 MHz QPH housekeeping reference
(* altera_attribute = "-name IO_STANDARD LVDS; -name INPUT_TERMINATION DIFFERENTIAL" *)  input                     pin_lvds_inp_vl_QPI_SYSCLK_DP,                    // LVDS 100 MHz QPI SYSCLK
(* altera_attribute = "-name IO_STANDARD LVDS; -name INPUT_TERMINATION DIFFERENTIAL" *)  input                     pin_lvds_inp_vl_FABCLK_200_DP,                    // LVDS 200 MHz QPH fabric reference
(* altera_attribute = "-name IO_STANDARD LVDS; -name INPUT_TERMINATION DIFFERENTIAL" *)  input                     pin_lvds_inp_vl_RSVCLK_200_DP,                    // LVDS 200 MHz QPH reserved reference
(* altera_attribute = "-name IO_STANDARD \"2.5-V\"" *)  input                     pin_cmos25_inp_vl_QPI_RESET_N,                    // Active-low reset to SYSCLK

  // PCB PLL
(* altera_attribute = "-name IO_STANDARD \"2.5-V\"; -name SLEW_RATE 1; -name CURRENT_STRENGTH_NEW 16MA" *)  output                    pin_cmos25_out_vl_LMK_CLKuWire_N,                 // PCB PLL uWire Clock
(* altera_attribute = "-name IO_STANDARD \"2.5-V\"; -name SLEW_RATE 1; -name CURRENT_STRENGTH_NEW 16MA" *)  output                    pin_cmos25_out_vl_LMK_DATAuWire_N,                // PCB PLL uWire Data
(* altera_attribute = "-name IO_STANDARD \"2.5-V\"; -name SLEW_RATE 1; -name CURRENT_STRENGTH_NEW 16MA" *)  output                    pin_cmos25_out_vl_LMK_LEuWire_N,                  // PCB PLL uWire Latch Enable
(* altera_attribute = "-name IO_STANDARD \"2.5-V\"; -name SLEW_RATE 1; -name CURRENT_STRENGTH_NEW 16MA" *)  output                    pin_cmos25_out_vl_LMK_SYNC_N,                     // PCB PLL Sync for start
(* altera_attribute = "-name IO_STANDARD \"2.5-V\"" *)  input                     pin_cmos25_inp_vl_LMK_Status_LD_N,                // PCB PLL Lock Detect & readback

  // Transceiver reference clock and QPI pins
(* altera_attribute = "-name IO_STANDARD LVDS" *)  input                     pin_lvds_inp_vl_ATXCK0_x00_DP,                    // HSSI REFCLK

(* altera_attribute = "-name IO_STANDARD \"1.4-V PCML\"" *)  input                     pin_qpi_bid_vl_QPI0_CLKRX_DP,                     // Rx clock for QPI data
(* altera_attribute = "-name IO_STANDARD \"1.4-V PCML\"" *)  input              [19:0] pin_qpi_bid_vl20_QPI0_DRX_DP,                     // Rx data

(* altera_attribute = "-name IO_STANDARD \"1.4-V PCML\"" *)  output                    pin_qpi_bid_vl_QPI0_CLKTX_DP,                     // Tx clock for QPI data
(* altera_attribute = "-name IO_STANDARD \"1.4-V PCML\"" *)  output             [19:0] pin_qpi_bid_vl20_QPI0_DTX_DP,                     // Tx data

(* altera_attribute = "-name IO_STANDARD \"1.4-V PCML\"" *)  input               [2:0] pin_qpi_bid_vl3_QPI0_RsvdRX_DP,                   // Reserved Rx data

(* altera_attribute = "-name IO_STANDARD \"1.4-V PCML\"" *)  output              [2:0] pin_qpi_bid_vl3_QPI0_RsvdTX_DP,                   // Reserved Tx data


  // QPH PCB control and status
(* altera_attribute = "-name IO_STANDARD \"2.5-V\"; -name SLEW_RATE 1; -name CURRENT_STRENGTH_NEW 16MA" *)  output              [7:0] pin_cmos25od_out_vl8_LED_G_N,                     // FPGA Status LEDs, green
(* altera_attribute = "-name IO_STANDARD \"2.5-V\"; -name SLEW_RATE 1; -name CURRENT_STRENGTH_NEW 16MA" *)  output              [7:0] pin_cmos25od_out_vl8_LED_R_N,                     // FPGA Status LEDs, red

  // Stub
(* altera_attribute = "-name IO_STANDARD \"SSTL-12\"" *)  input                     pin_cmosVtt_inp_vl_QPI_PWRGOOD,                   // Actually a master reset that can be retriggered
(* altera_attribute = "-name IO_STANDARD \"SSTL-12\"" *)  input                     pin_cmosVtt_inp_vl_QPI_RESET_N,                   // Active-low reset to SYSCLK
(* altera_attribute = "-name IO_STANDARD \"1.2-V\"; -name SLEW_RATE 1; -name CURRENT_STRENGTH_NEW 8MA" *)  inout                     pin_cmosVttod_bid_vl_PECI_StrongPu,               // PECI sideband
(* altera_attribute = "-name IO_STANDARD \"1.2-V\"; -name SLEW_RATE 1; -name CURRENT_STRENGTH_NEW 8MA" *)  output                    pin_cmosVttod_out_vl_PECI_WeakPd,
(* altera_attribute = "-name IO_STANDARD \"1.2-V\"; -name SLEW_RATE 1; -name CURRENT_STRENGTH_NEW 8MA" *)  output                    pin_cmosVttod_out_vl_DDR_SCL_C01,                 // SPD
(* altera_attribute = "-name IO_STANDARD \"1.2-V\"; -name SLEW_RATE 1; -name CURRENT_STRENGTH_NEW 8MA" *)  inout                     pin_cmosVttod_bid_vl_DDR_SDA_C01,
(* altera_attribute = "-name IO_STANDARD \"1.2-V\"; -name SLEW_RATE 1; -name CURRENT_STRENGTH_NEW 8MA" *)  output                    pin_cmosVttod_out_vl_DDR_SCL_C23,
(* altera_attribute = "-name IO_STANDARD \"1.2-V\"; -name SLEW_RATE 1; -name CURRENT_STRENGTH_NEW 8MA" *)  inout                     pin_cmosVttod_bid_vl_DDR_SDA_C23,
(* altera_attribute = "-name IO_STANDARD \"1.5-V\"" *)  input                     pin_cmos15_inp_vl_DRAM_PWR_OK_C01,                // DRAM power okay
(* altera_attribute = "-name IO_STANDARD \"1.5-V\"" *)  input                     pin_cmos15_inp_vl_DRAM_PWR_OK_C23,
(* altera_attribute = "-name IO_STANDARD \"SSTL-12\"" *)  input                     pin_cmosVtt_inp_vl_EAR_N,                         // Sideband EAR
(* altera_attribute = "-name IO_STANDARD \"SSTL-12\"" *)  input                     pin_cmosVtt_inp_vl_CPU_ONLY_RESET_N,              // Sideband CPU only reset
(* altera_attribute = "-name IO_STANDARD \"SSTL-12\"" *)  input               [1:0] pin_cmosVtt_inp_vl2_SOCKET_ID,                    // Sideband Socket ID
(* altera_attribute = "-name IO_STANDARD \"2.5-V\"" *)  input                     pin_cmos25_inp_vl_PECI_FPGA_IN,                   // Alternate PECI
(* altera_attribute = "-name IO_STANDARD \"2.5-V\"; -name SLEW_RATE 1; -name CURRENT_STRENGTH_NEW 8MA" *)  output                    pin_cmos25_out_vl_PECI_FPGA_OUT,
(* altera_attribute = "-name IO_STANDARD \"2.5-V\"" *)  input                     pin_cmos25_inp_vl_FPGA_RST_N,                     // Alternate reset (from CPLD)
(* altera_attribute = "-name IO_STANDARD \"2.5-V\"" *)  input               [3:0] pin_cmos25_inp_vl4_FPGA_STRAP,                    // PCB strap signals
(* altera_attribute = "-name IO_STANDARD \"2.5-V\"; -name SLEW_RATE 1; -name CURRENT_STRENGTH_NEW 8MA" *)  output                    pin_cmos25_out_vl_STUB                            // Stub for development
);

    wire   [60:0] ffs_vl61_LP32ui_sy2lp_C0TxHdr;            /* synthesis keep=1 */  // System to LP header 
    wire          ffs_vl_LP32ui_sy2lp_C0TxRdValid;          /* synthesis keep=1 */  // TxRdHdr valid signals                                                   
    wire   [60:0] ffs_vl61_LP32ui_sy2lp_C1TxHdr;            /* synthesis keep=1 */  // System to LP header
    wire  [511:0] ffs_vl512_LP32ui_sy2lp_C1TxData;          /* synthesis keep=1 */  // System to LP data 
    wire          ffs_vl_LP32ui_sy2lp_C1TxWrValid;          /* synthesis keep=1 */  // TxWrHdr valid signal
    wire          ffs_vl_LP32ui_sy2lp_C1TxIrValid;          /* synthesis keep=1 */  // Tx Interrupt valid signal
    wire   [17:0] ffs_vl18_LP32ui_lp2sy_C0RxHdr;            /* synthesis keep=1 */  // System to LP header
    wire  [511:0] ffs_vl512_LP32ui_lp2sy_C0RxData;          /* synthesis keep=1 */  // System to LP data 
    wire          ffs_vl_LP32ui_lp2sy_C0RxWrValid;          /* synthesis keep=1 */  // RxWrHdr valid signal 
    wire          ffs_vl_LP32ui_lp2sy_C0RxRdValid;          /* synthesis keep=1 */  // RxRdHdr valid signal
    wire          ffs_vl_LP32ui_lp2sy_C0RxCgValid;          /* synthesis keep=1 */  // RxCgHdr valid signal
    wire          ffs_vl_LP32ui_lp2sy_C0RxUgValid;          /* synthesis keep=1 */  // Rx Umsg Valid signal
    wire          ffs_vl_LP32ui_lp2sy_C0RxIrValid;          /* synthesis keep=1 */  // Rx Interrupt valid signal     
    wire   [17:0] ffs_vl18_LP32ui_lp2sy_C1RxHdr;            /* synthesis keep=1 */  // System to LP header (Channel 1)
    wire          ffs_vl_LP32ui_lp2sy_C1RxWrValid;          /* synthesis keep=1 */  // RxData valid signal (Channel 1)
    wire          ffs_vl_LP32ui_lp2sy_C1RxIrValid;          /* synthesis keep=1 */  // Rx Interrupt valid signal (Channel 1)
    wire          ffs_vl_LP32ui_lp2sy_C0TxAlmFull;          /* synthesis keep=1 */  // Channel 0 almost full
    wire          ffs_vl_LP32ui_lp2sy_C1TxAlmFull;          /* synthesis keep=1 */  // Channel 1 almost full
    wire          ffs_vl_LP32ui_lp2sy_InitDnForSys;         /* synthesis keep=1 */  // System layer is aok to run
    wire          vl_clk_LPdomain_32ui;                     /* synthesis keep=1 */  // 32ui link/protocol clock domain
    wire          vl_clk_LPdomain_16ui;                     /* synthesis keep=1 */  // 16ui link/protocol clock domain
    wire          ffs_vl_LP32ui_ph2lp_sync_reset_part_n;    /* synthesis keep=1 */  // System reset
    wire          ffs_vl_LP32ui_lp2sy_Reset_n;              /* synthesis keep=1 */  // AFU soft reset


ome_bot bot_ome(
  .pin_cmos25_inp_vl_QPI_PWRGOOD                (pin_cmos25_inp_vl_QPI_PWRGOOD),
  .pin_cmos25_inp_vl_HSECLK_112                 (pin_cmos25_inp_vl_HSECLK_112),
  .pin_lvds_inp_vl_QPI_SYSCLK_DP                (pin_lvds_inp_vl_QPI_SYSCLK_DP),
  .pin_lvds_inp_vl_FABCLK_200_DP                (pin_lvds_inp_vl_FABCLK_200_DP),
  .pin_lvds_inp_vl_RSVCLK_200_DP                (pin_lvds_inp_vl_RSVCLK_200_DP),
  .pin_cmos25_inp_vl_QPI_RESET_N                (pin_cmos25_inp_vl_QPI_RESET_N),

  .pin_cmos25_out_vl_LMK_CLKuWire_N             (pin_cmos25_out_vl_LMK_CLKuWire_N),
  .pin_cmos25_out_vl_LMK_DATAuWire_N            (pin_cmos25_out_vl_LMK_DATAuWire_N),
  .pin_cmos25_out_vl_LMK_LEuWire_N              (pin_cmos25_out_vl_LMK_LEuWire_N),
  .pin_cmos25_out_vl_LMK_SYNC_N                 (pin_cmos25_out_vl_LMK_SYNC_N),
  .pin_cmos25_inp_vl_LMK_Status_LD_N            (pin_cmos25_inp_vl_LMK_Status_LD_N),

  .pin_lvds_inp_vl_ATXCK0_x00_DP                (pin_lvds_inp_vl_ATXCK0_x00_DP),

  .pin_qpi_bid_vl_QPI0_CLKRX_DP                 (pin_qpi_bid_vl_QPI0_CLKRX_DP),
  .pin_qpi_bid_vl20_QPI0_DRX_DP                 (pin_qpi_bid_vl20_QPI0_DRX_DP),

  .pin_qpi_bid_vl_QPI0_CLKTX_DP                 (pin_qpi_bid_vl_QPI0_CLKTX_DP),
  .pin_qpi_bid_vl20_QPI0_DTX_DP                 (pin_qpi_bid_vl20_QPI0_DTX_DP),

  .pin_qpi_bid_vl3_QPI0_RsvdRX_DP               (pin_qpi_bid_vl3_QPI0_RsvdRX_DP),

  .pin_qpi_bid_vl3_QPI0_RsvdTX_DP               (pin_qpi_bid_vl3_QPI0_RsvdTX_DP),


  .pin_cmos25od_out_vl8_LED_G_N                 (pin_cmos25od_out_vl8_LED_G_N),
  .pin_cmos25od_out_vl8_LED_R_N                 (pin_cmos25od_out_vl8_LED_R_N),

  .pin_cmosVtt_inp_vl_QPI_PWRGOOD               (pin_cmosVtt_inp_vl_QPI_PWRGOOD),
  .pin_cmosVtt_inp_vl_QPI_RESET_N               (pin_cmosVtt_inp_vl_QPI_RESET_N),
  .pin_cmosVttod_bid_vl_PECI_StrongPu           (pin_cmosVttod_bid_vl_PECI_StrongPu),
  .pin_cmosVttod_out_vl_PECI_WeakPd             (pin_cmosVttod_out_vl_PECI_WeakPd),
  .pin_cmosVttod_out_vl_DDR_SCL_C01             (pin_cmosVttod_out_vl_DDR_SCL_C01),
  .pin_cmosVttod_bid_vl_DDR_SDA_C01             (pin_cmosVttod_bid_vl_DDR_SDA_C01),
  .pin_cmosVttod_out_vl_DDR_SCL_C23             (pin_cmosVttod_out_vl_DDR_SCL_C23),
  .pin_cmosVttod_bid_vl_DDR_SDA_C23             (pin_cmosVttod_bid_vl_DDR_SDA_C23),
  .pin_cmos15_inp_vl_DRAM_PWR_OK_C01            (pin_cmos15_inp_vl_DRAM_PWR_OK_C01),
  .pin_cmos15_inp_vl_DRAM_PWR_OK_C23            (pin_cmos15_inp_vl_DRAM_PWR_OK_C23),
  .pin_cmosVtt_inp_vl_EAR_N                     (pin_cmosVtt_inp_vl_EAR_N),
  .pin_cmosVtt_inp_vl_CPU_ONLY_RESET_N          (pin_cmosVtt_inp_vl_CPU_ONLY_RESET_N),
  .pin_cmosVtt_inp_vl2_SOCKET_ID                (pin_cmosVtt_inp_vl2_SOCKET_ID),
  .pin_cmos25_inp_vl_PECI_FPGA_IN               (pin_cmos25_inp_vl_PECI_FPGA_IN),
  .pin_cmos25_out_vl_PECI_FPGA_OUT              (pin_cmos25_out_vl_PECI_FPGA_OUT),
  .pin_cmos25_inp_vl_FPGA_RST_N                 (pin_cmos25_inp_vl_FPGA_RST_N),
  .pin_cmos25_inp_vl4_FPGA_STRAP                (pin_cmos25_inp_vl4_FPGA_STRAP),
  .pin_cmos25_out_vl_STUB                       (pin_cmos25_out_vl_STUB),
                                                                                    // CCI:  Core Cache Interface
  .ffs_LP32ui_vl61_sy2lp_C0TxHdr                (ffs_vl61_LP32ui_sy2lp_C0TxHdr),
  .ffs_LP32ui_vl_sy2lp_C0TxRdValid              (ffs_vl_LP32ui_sy2lp_C0TxRdValid),
  .ffs_LP32ui_vl61_sy2lp_C1TxHdr                (ffs_vl61_LP32ui_sy2lp_C1TxHdr),
  .ffs_LP32ui_vl512_sy2lp_C1TxData              (ffs_vl512_LP32ui_sy2lp_C1TxData),
  .ffs_LP32ui_vl_sy2lp_C1TxWrValid              (ffs_vl_LP32ui_sy2lp_C1TxWrValid),
  .ffs_LP32ui_vl_sy2lp_C1TxIrValid              (ffs_vl_LP32ui_sy2lp_C1TxIrValid),
  .ffs_LP32ui_vl18_lp2sy_C0RxHdr                (ffs_vl18_LP32ui_lp2sy_C0RxHdr),
  .ffs_LP32ui_vl512_lp2sy_C0RxData              (ffs_vl512_LP32ui_lp2sy_C0RxData),
  .ffs_LP32ui_vl_lp2sy_C0RxWrValid              (ffs_vl_LP32ui_lp2sy_C0RxWrValid),
  .ffs_LP32ui_vl_lp2sy_C0RxRdValid              (ffs_vl_LP32ui_lp2sy_C0RxRdValid),
  .ffs_LP32ui_vl_lp2sy_C0RxCgValid              (ffs_vl_LP32ui_lp2sy_C0RxCgValid),
  .ffs_LP32ui_vl_lp2sy_C0RxUgValid              (ffs_vl_LP32ui_lp2sy_C0RxUgValid),
  .ffs_LP32ui_vl_lp2sy_C0RxIrValid              (ffs_vl_LP32ui_lp2sy_C0RxIrValid),
  .ffs_LP32ui_vl18_lp2sy_C1RxHdr                (ffs_vl18_LP32ui_lp2sy_C1RxHdr),
  .ffs_LP32ui_vl_lp2sy_C1RxWrValid              (ffs_vl_LP32ui_lp2sy_C1RxWrValid),
  .ffs_LP32ui_vl_lp2sy_C1RxIrValid              (ffs_vl_LP32ui_lp2sy_C1RxIrValid),
  .ffs_LP32ui_vl_lp2sy_C0TxAlmFull              (ffs_vl_LP32ui_lp2sy_C0TxAlmFull),
  .ffs_LP32ui_vl_lp2sy_C1TxAlmFull              (ffs_vl_LP32ui_lp2sy_C1TxAlmFull),
  .ffs_LP32ui_vl_lp2sy_InitDnForSys             (ffs_vl_LP32ui_lp2sy_InitDnForSys),
  .vl_clk_LPdomain_32ui                         (vl_clk_LPdomain_32ui),
  .vl_clk_LPdomain_16ui                         (vl_clk_LPdomain_16ui),                     
  .ffs_LP32ui_vl_ph2lp_sync_reset_part_n        (ffs_vl_LP32ui_ph2lp_sync_reset_part_n),     
  .ffs_LP32ui_vl_lp2sy_Reset_n                  (ffs_vl_LP32ui_lp2sy_Reset_n) // AFU Reset
 
);

// CCI:  Core Cache Interface
    cci_std_afu cci_std_afu (                                          // Link/Protocol (LP) clocks and reset
                            .vl_clk_LPdomain_32ui           (vl_clk_LPdomain_32ui),                     // 32ui link/protocol clock domain. Interface clock                
                            .vl_clk_LPdomain_16ui           (vl_clk_LPdomain_16ui),                     // 16ui link/protocol clock domain. Synchronous to interface clock
                            .ffs_vl_LP32ui_lp2sy_SystemReset_n(ffs_vl_LP32ui_ph2lp_sync_reset_part_n),  // System Reset
                            .ffs_vl_LP32ui_lp2sy_SoftReset_n  (ffs_vl_LP32ui_lp2sy_Reset_n),            // CCI-S soft reset
                            
                            // Native CCI Interface (cache line interface for back end)
                            /* Channel 0 can receive READ, WRITE, WRITE CSR responses.*/
                            .ffs_vl18_LP32ui_lp2sy_C0RxHdr  (ffs_vl18_LP32ui_lp2sy_C0RxHdr),             // System to LP header
                            .ffs_vl512_LP32ui_lp2sy_C0RxData(ffs_vl512_LP32ui_lp2sy_C0RxData),           // System to LP data 
                            .ffs_vl_LP32ui_lp2sy_C0RxWrValid(ffs_vl_LP32ui_lp2sy_C0RxWrValid),           // RxWrHdr valid signal 
                            .ffs_vl_LP32ui_lp2sy_C0RxRdValid(ffs_vl_LP32ui_lp2sy_C0RxRdValid),           // RxRdHdr valid signal
                            .ffs_vl_LP32ui_lp2sy_C0RxCgValid(ffs_vl_LP32ui_lp2sy_C0RxCgValid),           // RxCgHdr valid signal
                            .ffs_vl_LP32ui_lp2sy_C0RxUgValid(ffs_vl_LP32ui_lp2sy_C0RxUgValid),           // Rx Umsg Valid signal
                            .ffs_vl_LP32ui_lp2sy_C0RxIrValid(ffs_vl_LP32ui_lp2sy_C0RxIrValid),           // Rx Interrupt valid signal

                            /* Channel 1 reserved for WRITE RESPONSE ONLY */
                            .ffs_vl18_LP32ui_lp2sy_C1RxHdr  (ffs_vl18_LP32ui_lp2sy_C1RxHdr),             // System to LP header (Channel 1)
                            .ffs_vl_LP32ui_lp2sy_C1RxWrValid(ffs_vl_LP32ui_lp2sy_C1RxWrValid),           // RxData valid signal (Channel 1)
                            .ffs_vl_LP32ui_lp2sy_C1RxIrValid(ffs_vl_LP32ui_lp2sy_C1RxIrValid),           // Rx Interrupt valid signal (Channel 1)

                            /* Tx push flow control */
                            .ffs_vl_LP32ui_lp2sy_C0TxAlmFull(ffs_vl_LP32ui_lp2sy_C0TxAlmFull),           // Channel 0 almost full
                            .ffs_vl_LP32ui_lp2sy_C1TxAlmFull(ffs_vl_LP32ui_lp2sy_C1TxAlmFull),           // Channel 1 almost full
        
                            .ffs_vl_LP32ui_lp2sy_InitDnForSys(ffs_vl_LP32ui_lp2sy_InitDnForSys),          // System layer is aok to run

                            /*Channel 0 reserved for READ REQUESTS ONLY */        
                            .ffs_vl61_LP32ui_sy2lp_C0TxHdr   (ffs_vl61_LP32ui_sy2lp_C0TxHdr),             // System to LP header 
                            .ffs_vl_LP32ui_sy2lp_C0TxRdValid (ffs_vl_LP32ui_sy2lp_C0TxRdValid),           // TxRdHdr valid signals 

                            /*Channel 1 reserved for WRITE REQUESTS ONLY */       
                            .ffs_vl61_LP32ui_sy2lp_C1TxHdr   (ffs_vl61_LP32ui_sy2lp_C1TxHdr),             // System to LP header
                            .ffs_vl512_LP32ui_sy2lp_C1TxData (ffs_vl512_LP32ui_sy2lp_C1TxData),           // System to LP data 
                            .ffs_vl_LP32ui_sy2lp_C1TxWrValid (ffs_vl_LP32ui_sy2lp_C1TxWrValid),           // TxWrHdr valid signal
                            .ffs_vl_LP32ui_sy2lp_C1TxIrValid (ffs_vl_LP32ui_sy2lp_C1TxIrValid)            // Tx Interrupt valid signal
                            );



endmodule
