# --- I2C Clock (SCL) ---
set_property PACKAGE_PIN E12 [get_ports j2_scl]
set_property IOSTANDARD LVCMOS18 [get_ports j2_scl]
set_property PULLUP true [get_ports j2_scl]

# --- I2C Data (SDA) ---
set_property PACKAGE_PIN D10 [get_ports j2_sda]
set_property IOSTANDARD LVCMOS18 [get_ports j2_sda]
set_property PULLUP true [get_ports j2_sda]

# --- Timing Exceptions ---
set_false_path -from [get_ports {j2_scl j2_sda}]
set_false_path -to   [get_ports {j2_scl j2_sda}]