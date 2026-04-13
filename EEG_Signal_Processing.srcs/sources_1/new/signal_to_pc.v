`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/26/2026 08:49:09 AM
// Design Name: 
// Module Name: signal_to_pc
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


module signal_to_pc#(
    parameter CLK_FREQ    = 100_000_000,
    parameter SAMPLE_RATE = 1000,
    parameter SPI_DIV     = 50
)(
    input  wire clk,
    input  wire rst,
    output reg  sclk,
    output reg  cs_n,
    input  wire sdo,
    output reg [15:0] m_axis_tdata,
    output reg        m_axis_tvalid,
    input  wire       m_axis_tready
);

    // =============================
    // Sampling Tick
    // =============================
    localparam SAMPLE_DIV = CLK_FREQ / SAMPLE_RATE;
    reg [31:0] sample_cnt;
    reg sample_tick;

    always @(posedge clk) begin
        if (rst) begin
            sample_cnt  <= 0;
            sample_tick <= 0;
        end else begin
            if (sample_cnt == SAMPLE_DIV - 1) begin
                sample_cnt  <= 0;
                sample_tick <= 1;
            end else begin
                sample_cnt  <= sample_cnt + 1;
                sample_tick <= 0;
            end
        end
    end

    // =============================
    // Sample Pending Latch         <- FIX 2
    // =============================
    reg sample_pend;

    always @(posedge clk) begin
        if (rst) begin
            sample_pend <= 0;
        end else begin
            if (sample_tick)        sample_pend <= 1;
            else if (state == READ) sample_pend <= 0;
        end
    end

    // =============================
    // SPI Clock Divider
    // =============================
    reg [7:0] spi_cnt;
    reg spi_en;

    always @(posedge clk) begin
        if (rst) begin
            spi_cnt <= 0;
            spi_en  <= 0;
        end else begin
            if (spi_cnt == SPI_DIV - 1) begin
                spi_cnt <= 0;
                spi_en  <= 1;
            end else begin
                spi_cnt <= spi_cnt + 1;
                spi_en  <= 0;
            end
        end
    end

    // =============================
    // SPI FSM
    // =============================
    reg [4:0] bit_cnt;
    reg [15:0] shift_reg;
    reg [1:0] state;
    localparam IDLE = 0, READ = 1, DONE = 2;

    always @(posedge clk) begin
        if (rst) begin
            state     <= IDLE;
            cs_n      <= 1;
            sclk      <= 0;
            bit_cnt   <= 0;
            shift_reg <= 0;
        end else if (spi_en) begin
            case (state)
                IDLE: begin
                    if (sample_pend) begin
                        cs_n      <= 0;
                        bit_cnt   <= 0;
                        shift_reg <= 0;
                        state     <= READ;
                    end
                end

                READ: begin
                    sclk <= ~sclk;
                    // FIX 1: read old sclk value - 0→1 is a rising edge
                    if (sclk == 1'b0) begin
                        shift_reg <= {shift_reg[14:0], sdo};
                        bit_cnt   <= bit_cnt + 1;
                        if (bit_cnt == 15)
                            state <= DONE;
                    end
                end

                DONE: begin
                    cs_n  <= 1;
                    sclk  <= 0;
                    state <= IDLE;
                end
            endcase
        end
    end

    // =============================
    // AXI Stream Output            <- FIX 3
    // =============================
    reg done_pulse;

    always @(posedge clk)
        done_pulse <= spi_en && (state == DONE);

    always @(posedge clk) begin
        if (rst) begin
            m_axis_tvalid <= 0;
            m_axis_tdata  <= 0;
        end else begin
            if (done_pulse) begin
                m_axis_tdata  <= shift_reg;
                m_axis_tvalid <= 1;
            end else if (m_axis_tvalid && m_axis_tready) begin
                m_axis_tvalid <= 0;
            end
        end
    end

endmodule
