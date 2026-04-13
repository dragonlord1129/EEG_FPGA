//Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
//Copyright 2022-2024 Advanced Micro Devices, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2024.2 (lin64) Build 5239630 Fri Nov 08 22:34:34 MST 2024
//Date        : Sat Mar 28 17:10:26 2026
//Host        : dragonlord-Legion-5-15ARH7H running 64-bit Ubuntu 24.04.4 LTS
//Command     : generate_target signal_receiver_wrapper.bd
//Design      : signal_receiver_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module signal_receiver_wrapper
   (som240_1_connector_pmod_iic_scl_io,
    som240_1_connector_pmod_iic_sda_io);
  inout som240_1_connector_pmod_iic_scl_io;
  inout som240_1_connector_pmod_iic_sda_io;

  wire som240_1_connector_pmod_iic_scl_i;
  wire som240_1_connector_pmod_iic_scl_io;
  wire som240_1_connector_pmod_iic_scl_o;
  wire som240_1_connector_pmod_iic_scl_t;
  wire som240_1_connector_pmod_iic_sda_i;
  wire som240_1_connector_pmod_iic_sda_io;
  wire som240_1_connector_pmod_iic_sda_o;
  wire som240_1_connector_pmod_iic_sda_t;

  signal_receiver signal_receiver_i
       (.som240_1_connector_pmod_iic_scl_i(som240_1_connector_pmod_iic_scl_i),
        .som240_1_connector_pmod_iic_scl_o(som240_1_connector_pmod_iic_scl_o),
        .som240_1_connector_pmod_iic_scl_t(som240_1_connector_pmod_iic_scl_t),
        .som240_1_connector_pmod_iic_sda_i(som240_1_connector_pmod_iic_sda_i),
        .som240_1_connector_pmod_iic_sda_o(som240_1_connector_pmod_iic_sda_o),
        .som240_1_connector_pmod_iic_sda_t(som240_1_connector_pmod_iic_sda_t));
  IOBUF som240_1_connector_pmod_iic_scl_iobuf
       (.I(som240_1_connector_pmod_iic_scl_o),
        .IO(som240_1_connector_pmod_iic_scl_io),
        .O(som240_1_connector_pmod_iic_scl_i),
        .T(som240_1_connector_pmod_iic_scl_t));
  IOBUF som240_1_connector_pmod_iic_sda_iobuf
       (.I(som240_1_connector_pmod_iic_sda_o),
        .IO(som240_1_connector_pmod_iic_sda_io),
        .O(som240_1_connector_pmod_iic_sda_i),
        .T(som240_1_connector_pmod_iic_sda_t));
endmodule
