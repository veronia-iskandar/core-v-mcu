// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.


module fc_subsystem #(
    parameter USE_FPU             = 1,
    parameter USE_HWPE            = 1,
    parameter N_EXT_PERF_COUNTERS = 1,
    parameter EVENT_ID_WIDTH      = 8,
    parameter PER_ID_WIDTH        = 32,
    parameter NB_HWPE_PORTS       = 4,
    parameter GDP_NVPE          = 1
) (
    input logic clk_i,
    input logic rst_ni,
    input logic test_en_i,

    XBAR_TCDM_BUS.Master l2_data_master,
    XBAR_TCDM_BUS.Master l2_instr_master,

    input logic        fetch_en_i,
    input logic [31:0] boot_addr_i,
    input logic        debug_req_i,

    input  logic [31:0] events_i,  // interrupts to cpu
    output       [ 4:0] core_irq_ack_id_o,
    output              core_irq_ack_o,

    output logic stoptimer_o,
    output logic supervisor_mode_o
);

  import cv32e40p_apu_core_pkg::*;

  // Interrupt signals
  logic        core_irq_req;
  logic        core_irq_sec;
  logic [ 4:0] core_irq_id;
  logic [ 4:0] core_irq_ack_id;
  logic        core_irq_ack;
  logic [31:0] core_irq_x;
  logic [31:0] s_irq_o;


  // Boot address, core id, cluster id, fethc enable and core_status
  logic [31:0] boot_addr;
  logic        fetch_en_int;
  logic        core_busy_int;
  logic        perf_counters_int;
  logic [31:0] hart_id;

  //EU signals
  logic        core_clock_en;
  logic        fetch_en_eu;

  //Core Instr Bus
  logic [31:0] core_instr_addr, core_instr_rdata;
  logic core_instr_req, core_instr_gnt, core_instr_rvalid, core_instr_err;

  //Core Data Bus
  logic [31:0] core_data_addr, core_data_rdata, core_data_wdata;
  logic core_data_req, core_data_gnt, core_data_rvalid, core_data_err;
  logic       core_data_we;
  logic [3:0] core_data_be;
  logic is_scm_instr_req, is_scm_data_req;
  
      // Data crossbar slave 1
    logic                         data_req_xbr_s1;
    logic                         data_gnt_xbr_s1;
    logic                         data_rvalid_xbr_s1;
    logic [31:0]                  data_addr_xbr_s1;
    logic                         data_we_xbr_s1;
    logic [3:0]                   data_be_xbr_s1;
    logic [31:0]                  data_rdata_xbr_s1;
    logic [31:0]                  data_wdata_xbr_s1;
    // Data crossbar master 1 (CPU)
    logic                         data_req_xbr_m1;
    logic                         data_gnt_xbr_m1;
    logic                         data_rvalid_xbr_m1;
    logic [31:0]                  data_addr_xbr_m1;
    logic                         data_we_xbr_m1;
    logic [3:0]                   data_be_xbr_m1;
    logic [31:0]                  data_rdata_xbr_m1;
    logic [31:0]                  data_wdata_xbr_m1;
    // Data crossbar master 2 (NVPE)
    logic                         data_req_xbr_m2;
    logic                         data_gnt_xbr_m2;
    logic                         data_rvalid_xbr_m2;
    logic [31:0]                  data_addr_xbr_m2;
    logic                         data_we_xbr_m2;
    logic [3:0]                   data_be_xbr_m2;
    logic [31:0]                  data_rdata_xbr_m2;
    logic [31:0]                  data_wdata_xbr_m2;

    logic core_halt;


  logic [                31:0]       r_int;


  // APU Core to FP Wrapper
  logic                              apu_req;
  logic [  2:0][31:0] apu_operands;
  logic [     5:0]       apu_op;
  logic [14:0]       apu_flags;


  logic [31:0]                  apu_result;
  logic [4:0]                   apu_flags_r; //check width


  // APU FP Wrapper to Core
  logic                              apu_gnt;
  logic                              apu_rvalid;
  logic [                31:0]       apu_rdata;
  logic [APU_NUSFLAGS_CPU-1:0]       apu_rflags;

  assign perf_counters_int = 1'b0;
  assign fetch_en_int = fetch_en_eu & fetch_en_i;

  assign hart_id = '0;

  XBAR_TCDM_BUS core_data_bus ();
  XBAR_TCDM_BUS core_instr_bus ();

  //********************************************************
  //************ CORE DEMUX (TCDM vs L2) *******************
  //********************************************************
  assign l2_data_master.req    = data_req_xbr_s1;
  assign l2_data_master.add    = data_addr_xbr_s1;
  assign l2_data_master.wen    = ~data_we_xbr_s1;
  assign l2_data_master.wdata  = data_wdata_xbr_s1;
  assign l2_data_master.be     = data_be_xbr_s1;
  assign data_gnt_xbr_s1         = l2_data_master.gnt;
  assign data_rvalid_xbr_s1      = l2_data_master.r_valid;
  assign data_rdata_xbr_s1       = l2_data_master.r_rdata;
  assign core_data_err         = l2_data_master.r_opc;


  assign l2_instr_master.req   = core_instr_req;
  assign l2_instr_master.add   = core_instr_addr;
  assign l2_instr_master.wen   = 1'b1;
  assign l2_instr_master.wdata = '0;
  assign l2_instr_master.be    = 4'b1111;
  assign core_instr_gnt        = l2_instr_master.gnt;
  assign core_instr_rvalid     = l2_instr_master.r_valid;
  assign core_instr_rdata      = l2_instr_master.r_rdata;
  assign core_instr_err        = l2_instr_master.r_opc;

  //********************************************************
  //************ RISCV CORE ********************************
  //********************************************************

  // OpenHW Group CV32E40P
  assign boot_addr             = boot_addr_i;

  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (~rst_ni) r_int <= 0;
    else begin
      for (int i = 0; i < 32; i++) begin
        if (core_irq_ack_o && (core_irq_ack_id_o == i)) r_int[i] <= 0;
        else r_int[i] <= events_i[i] | r_int[i];
      end
    end
  end  // always_ff @ (posedge clk_i, negedge rst_ni)



  cv32e40p_core #(
      .FPU(`USE_FPU),
      .PULP_XPULP(1),
      .GDP_NVPE         (GDP_NVPE)
  ) lFC_CORE (
      .clk_i              (clk_i),
      .rst_ni             (rst_ni),
      .pulp_clock_en_i    (1'b1),
      .scan_cg_en_i       (test_en_i),
      .boot_addr_i        (boot_addr),
      .mtvec_addr_i       ('0),
      .dm_halt_addr_i     (32'h1A110800),
      .hart_id_i          (hart_id),
      .dm_exception_addr_i('0),

      // Instruction Memory Interface
      .instr_addr_o  (core_instr_addr),
      .instr_req_o   (core_instr_req),
      .instr_rdata_i (core_instr_rdata),
      .instr_gnt_i   (core_instr_gnt),
      .instr_rvalid_i(core_instr_rvalid),

      // Data memory interface
      .data_addr_o  (data_addr_xbr_m1),
      .data_req_o   (data_req_xbr_m1),
      .data_be_o    (data_be_xbr_m1),
      .data_rdata_i (data_rdata_xbr_m1),
      .data_we_o    (data_we_xbr_m1),
      .data_gnt_i   (data_gnt_xbr_m1),
      .data_wdata_o (data_wdata_xbr_m1),
      .data_rvalid_i(data_rvalid_xbr_m1),

      // apu-interconnect
      // handshake signals
      .apu_req_o     (apu_req),
      .apu_gnt_i     (apu_gnt),
      .apu_operands_o(apu_operands),
      .apu_op_o      (apu_op),
      .apu_flags_o   (apu_flags),
      .apu_rvalid_i  (apu_rvalid),
      .apu_result_i  (apu_result),
      .apu_flags_i   (apu_flags_r),


      .irq_i    (r_int),
      .irq_ack_o(core_irq_ack_o),
      .irq_id_o (core_irq_ack_id_o),

      .debug_req_i      (debug_req_i),
      .debug_havereset_o(),
      .debug_running_o  (),
      .debug_halted_o   (stoptimer_o),
      .fetch_enable_i   (fetch_en_i),
      .core_sleep_o     (core_sleep_o),
      .apu_core_halt          ( core_halt )
  );
  assign supervisor_mode_o = 1'b1;

    cv32e40n_data_xbar xbar_mux
       (.clk_i                  ( clk_i                     ),
        .rst_ni                 ( rst_ni                    ),

        .data_req_xbr_s1_o      ( data_req_xbr_s1           ),
        .data_gnt_xbr_s1_i      ( data_gnt_xbr_s1           ),
        .data_rvalid_xbr_s1_i   ( data_rvalid_xbr_s1        ),
        .data_addr_xbr_s1_o     ( data_addr_xbr_s1          ),
        .data_we_xbr_s1_o       ( data_we_xbr_s1            ),
        .data_be_xbr_s1_o       ( data_be_xbr_s1            ),
        .data_rdata_xbr_s1_i    ( data_rdata_xbr_s1         ),
        .data_wdata_xbr_s1_o    ( data_wdata_xbr_s1         ),

        .data_req_xbr_m1_i      ( data_req_xbr_m1           ),
        .data_gnt_xbr_m1_o      ( data_gnt_xbr_m1           ),
        .data_rvalid_xbr_m1_o   ( data_rvalid_xbr_m1        ),
        .data_addr_xbr_m1_i     ( data_addr_xbr_m1          ),
        .data_we_xbr_m1_i       ( data_we_xbr_m1            ),
        .data_be_xbr_m1_i       ( data_be_xbr_m1            ),
        .data_rdata_xbr_m1_o    ( data_rdata_xbr_m1         ),
        .data_wdata_xbr_m1_i    ( data_wdata_xbr_m1         ),

        .data_req_xbr_m2_i      ( data_req_xbr_m2           ),
        .data_gnt_xbr_m2_o      ( data_gnt_xbr_m2           ),
        .data_rvalid_xbr_m2_o   ( data_rvalid_xbr_m2        ),
        .data_addr_xbr_m2_i     ( data_addr_xbr_m2          ),
        .data_we_xbr_m2_i       ( data_we_xbr_m2            ),
        .data_be_xbr_m2_i       ( data_be_xbr_m2            ),
        .data_rdata_xbr_m2_o    ( data_rdata_xbr_m2         ),
        .data_wdata_xbr_m2_i    ( data_wdata_xbr_m2         ));

    accelerator_top a_top
       (.apu_result(apu_result),
        .apu_flags_o(apu_flags_r),
        .apu_gnt(apu_gnt),
        .apu_rvalid(apu_rvalid),
        .clk(clk_i),
        .n_reset(rst_ni),
        .apu_req(apu_req),
        .apu_operands_i(apu_operands),
        .apu_op(apu_op),
        .apu_flags_i(apu_flags),
        .data_req_o(data_req_xbr_m2),
        .data_gnt_i(data_gnt_xbr_m2),
        .data_rvalid_i(data_rvalid_xbr_m2),
        .data_we_o(data_we_xbr_m2),
        .data_be_o(data_be_xbr_m2),
        .data_addr_o(data_addr_xbr_m2),
        .data_wdata_o(data_wdata_xbr_m2),
        .data_rdata_i(data_rdata_xbr_m2),
        .core_halt_o(core_halt));


endmodule

