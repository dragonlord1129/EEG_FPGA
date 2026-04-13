`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/26/2026 09:42:04 AM
// Design Name: 
// Module Name: testbench
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module testbench
    reg clk;
    reg rst;

    wire sclk;
    wire cs_n;
    reg  sdo;

    wire [15:0] m_axis_tdata;
    wire        m_axis_tvalid;
    reg         m_axis_tready;

    signal_to_pc #(
        .CLK_FREQ   (100_000_000),
        .SAMPLE_RATE(1000),
        .SPI_DIV    (10)
    ) dut (
        .clk          (clk),
        .rst          (rst),
        .sclk         (sclk),
        .cs_n         (cs_n),
        .sdo          (sdo),
        .m_axis_tdata (m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready)
    );

    initial clk = 0;
    always  #5 clk = ~clk;

    reg [15:0] test_data = 16'hA5A5;
    integer    bit_index;

    // Pre-drive MSB synchronously with CS fall
    always @(negedge cs_n) begin
        bit_index = 0;
        sdo       = test_data[15];
    end

    // FIX: use bit_index directly (already updated by preceding posedge),
    //      no guard needed - bit_index naturally caps at 15
    always @(negedge sclk) begin
        if (!cs_n)
            sdo <= test_data[15 - bit_index];
    end

    // Advance index on each rising edge the master clocks in a bit
    always @(posedge sclk) begin
        if (!cs_n && bit_index < 15)
            bit_index <= bit_index + 1;
    end

    // Monitor
    always @(posedge clk) begin
        if (m_axis_tvalid && m_axis_tready) begin
            if (m_axis_tdata === test_data)
                $display("Time %0t | PASS - got 0x%04h", $time, m_axis_tdata);
            else
                $display("Time %0t | FAIL - got 0x%04h, expected 0x%04h",
                         $time, m_axis_tdata, test_data);
        end
    end

    initial begin
        $dumpfile("tb_pmod_ad2_stream.vcd");
        $dumpvars(0, tb_pmod_ad2_stream);
    end

    initial begin
        rst           = 1;
        sdo           = 0;
        m_axis_tready = 1;
        bit_index     = 0;
        #100;
        rst = 0;
        #10_000_000;
        $display("Simulation complete.");
        $finish;
    end

endmodule

   
