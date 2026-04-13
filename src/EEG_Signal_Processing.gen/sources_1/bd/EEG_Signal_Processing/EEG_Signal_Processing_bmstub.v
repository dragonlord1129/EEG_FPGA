// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2026 Advanced Micro Devices, Inc. All Rights Reserved.
// -------------------------------------------------------------------------------

`timescale 1 ps / 1 ps

(* BLOCK_STUB = "true" *)
module EEG_Signal_Processing (
  som240_1_connector_pmod_iic_scl_i,
  som240_1_connector_pmod_iic_scl_o,
  som240_1_connector_pmod_iic_scl_t,
  som240_1_connector_pmod_iic_sda_i,
  som240_1_connector_pmod_iic_sda_o,
  som240_1_connector_pmod_iic_sda_t
);

  (* X_INTERFACE_INFO = "xilinx.com:interface:iic:1.0 som240_1_connector_pmod_iic SCL_I" *)
  (* X_INTERFACE_MODE = "master som240_1_connector_pmod_iic" *)
  input som240_1_connector_pmod_iic_scl_i;
  (* X_INTERFACE_INFO = "xilinx.com:interface:iic:1.0 som240_1_connector_pmod_iic SCL_O" *)
  output som240_1_connector_pmod_iic_scl_o;
  (* X_INTERFACE_INFO = "xilinx.com:interface:iic:1.0 som240_1_connector_pmod_iic SCL_T" *)
  output som240_1_connector_pmod_iic_scl_t;
  (* X_INTERFACE_INFO = "xilinx.com:interface:iic:1.0 som240_1_connector_pmod_iic SDA_I" *)
  input som240_1_connector_pmod_iic_sda_i;
  (* X_INTERFACE_INFO = "xilinx.com:interface:iic:1.0 som240_1_connector_pmod_iic SDA_O" *)
  output som240_1_connector_pmod_iic_sda_o;
  (* X_INTERFACE_INFO = "xilinx.com:interface:iic:1.0 som240_1_connector_pmod_iic SDA_T" *)
  output som240_1_connector_pmod_iic_sda_t;

  // stub module has no contents

endmodule
