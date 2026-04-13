# =================================================
# XDC for Pmod AD2 → AXI DMA → Zynq UltraScale+
# =================================================

# ------------------------------------------------
# EXTERNAL / PHYSICAL PINS
# ------------------------------------------------

# I2C Clock (SCL)
set_property PACKAGE_PIN E12 [get_ports som240_1_connector_pmod_iic_scl_io]
set_property IOSTANDARD LVCMOS33 [get_ports som240_1_connector_pmod_iic_scl_io]
set_property PULLUP true [get_ports som240_1_connector_pmod_iic_scl_io]

# I2C Data (SDA)
set_property PACKAGE_PIN D10 [get_ports som240_1_connector_pmod_iic_sda_io]
set_property IOSTANDARD LVCMOS33 [get_ports som240_1_connector_pmod_iic_sda_io]
set_property PULLUP true [get_ports som240_1_connector_pmod_iic_sda_io]

# Optional: I2C interrupt from Pmod AD2
# set_property PACKAGE_PIN <pin_number> [get_ports i2c_interrupt]
# set_property IOSTANDARD LVCMOS33 [get_ports i2c_interrupt]

# Clock and Reset (if connected to top-level pins, otherwise leave internal)
# set_property PACKAGE_PIN <pin> [get_ports aclk aresetn]
# set_property IOSTANDARD LVCMOS33 [get_ports aclk aresetn]

# ------------------------------------------------
# INTERNAL / FPGA LOGIC PORTS
# ------------------------------------------------

# ------------------------------------------------
# OPTIONAL: Reduce DRC warnings for any remaining unspecified I/Os
# ------------------------------------------------
# set_property SEVERITY Warning [get_drc_checks NSTD-1]