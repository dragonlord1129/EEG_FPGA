`timescale 1ns/1ps

// AD7991 word format (passed raw on AXI-S):
//   [15:14] = 00 (always)
//   [13:12] = channel ID (0-3, set by ADC itself)
//   [11:0]  = 12-bit conversion result
//
// I2C tristate convention (identical to Digilent PmodAD2 IP):
//   _t = 0 → FPGA drives     (output)
//   _t = 1 → FPGA releases   (open-drain pull-up takes over)


module eeg_ad7991_acquisition #(
    parameter CLK_FREQ    = 100_000_000,
    parameter SAMPLE_RATE = 256,          // 256 Hz covers all EEG bands (Nyquist 128 Hz)
    parameter I2C_FREQ    = 400_000,      // 400 kHz fast-mode I2C
    parameter AD7991_ADDR = 7'h28         // AD7991-0: ADDR pin tied GND on PmodAD2
)(
    input  wire        clk,
    input  wire        rst_n,             // active-low (from proc_sys_reset)

    // I2C tristate - wire directly to Pmod_out_pin1/2 _i/_o/_t
    input  wire        scl_i,
    output reg         scl_o,
    output reg         scl_t,
    input  wire        sda_i,
    output reg         sda_o,
    output reg         sda_t,

    // AXI4-Stream master → AXI DMA S2MM
    output reg  [15:0] m_axis_tdata,
    output reg         m_axis_tvalid,
    output reg         m_axis_tlast,      // high on channel 3 (end of 4-ch frame)
    input  wire        m_axis_tready
);

    // -------------------------------------------------------------------------
    localparam integer I2C_QTR = CLK_FREQ / (I2C_FREQ * 4); // 62 @ 100 MHz/400 kHz
    localparam integer SMPL_D  = CLK_FREQ / SAMPLE_RATE;     // 390625 @ 256 Hz
    localparam integer INIT_D  = CLK_FREQ / 100;             // 10 ms power-on wait

    localparam [7:0] CFG_BYTE = 8'hF0;                       // all 4 channels enabled
    localparam [7:0] ADDR_W   = {AD7991_ADDR, 1'b0};         // 0x50
    localparam [7:0] ADDR_R   = {AD7991_ADDR, 1'b1};         // 0x51

    // -------------------------------------------------------------------------
    // 256 Hz sample tick
    // -------------------------------------------------------------------------
    reg [31:0] smpl_cnt;
    reg        smpl_tick;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin smpl_cnt<=0; smpl_tick<=0; end
        else if (smpl_cnt == SMPL_D-1) begin smpl_cnt<=0; smpl_tick<=1; end
        else begin smpl_cnt<=smpl_cnt+1; smpl_tick<=0; end
    end

    // -------------------------------------------------------------------------
    // I2C quarter-period tick  (T_I2C / 4)
    // -------------------------------------------------------------------------
    reg [15:0] i2c_cnt;
    reg        i2c_tick;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin i2c_cnt<=0; i2c_tick<=0; end
        else if (i2c_cnt == I2C_QTR-1) begin i2c_cnt<=0; i2c_tick<=1; end
        else begin i2c_cnt<=i2c_cnt+1; i2c_tick<=0; end
    end

    // -------------------------------------------------------------------------
    // FSM
    //   phase 0: SCL low  - set SDA
    //   phase 1: SCL rise
    //   phase 2: SCL high - sample SDA (for reads/ACK)
    //   phase 3: SCL fall
    // -------------------------------------------------------------------------
    localparam [4:0]
        S_INIT  = 5'd0,   S_CS   = 5'd1,   S_CA    = 5'd2,
        S_CAK   = 5'd3,   S_CD   = 5'd4,   S_CDK   = 5'd5,
        S_CP    = 5'd6,   S_IDLE = 5'd7,   S_RS    = 5'd8,
        S_RA    = 5'd9,   S_RAK  = 5'd10,  S_RH    = 5'd11,
        S_RHK   = 5'd12,  S_RL   = 5'd13,  S_RNACK = 5'd14,
        S_RP    = 5'd15,  S_EMIT = 5'd16;

    reg [4:0]  state;
    reg [1:0]  phase;
    reg [2:0]  bit_cnt;
    reg [1:0]  ch_cnt;
    reg [7:0]  tx_byte;
    reg [7:0]  rx_h, rx_l;
    reg [15:0] sample;
    reg [31:0] init_cnt;
    reg        ack_err;          // sticky NACK flag - connect to ILA for debug

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=S_INIT; phase<=0; bit_cnt<=7; ch_cnt<=0;
            tx_byte<=0; rx_h<=0; rx_l<=0; sample<=0;
            init_cnt<=0; ack_err<=0;
            scl_o<=1; scl_t<=1; sda_o<=1; sda_t<=1;
            m_axis_tdata<=0; m_axis_tvalid<=0; m_axis_tlast<=0;
        end else begin

            // AXI-S: clear valid once consumed
            if (m_axis_tvalid && m_axis_tready)
                begin m_axis_tvalid<=0; m_axis_tlast<=0; end

            case (state)

            // Power-on delay - 10 ms for AD7991 to settle
            S_INIT: begin
                scl_o<=1; scl_t<=1; sda_o<=1; sda_t<=1;
                if (init_cnt==INIT_D-1) begin init_cnt<=0; phase<=0; state<=S_CS; end
                else init_cnt<=init_cnt+1;
            end

            // CONFIG WRITE - START (SDA falls while SCL high)
            S_CS: if (i2c_tick) case (phase)
                0: begin scl_o<=1; scl_t<=1; sda_o<=1; sda_t<=1; phase<=1; end
                1: begin sda_o<=0; sda_t<=0; phase<=2; end            // SDA ↓
                2: begin scl_o<=0; scl_t<=0; phase<=3; end            // SCL ↓
                3: begin bit_cnt<=7; tx_byte<=ADDR_W; phase<=0; state<=S_CA; end
            endcase

            // Send byte MSB-first (shared pattern for all TX states)
            S_CA: if (i2c_tick) case (phase)
                0: begin sda_o<=tx_byte[bit_cnt]; sda_t<=0; phase<=1; end
                1: begin scl_o<=1; scl_t<=1; phase<=2; end
                2: begin phase<=3; end
                3: begin scl_o<=0; scl_t<=0; phase<=0;
                   if (bit_cnt==0) state<=S_CAK; else bit_cnt<=bit_cnt-1; end
            endcase

            // Receive slave ACK (SDA=0 means ACK)
            S_CAK: if (i2c_tick) case (phase)
                0: begin sda_t<=1; phase<=1; end
                1: begin scl_o<=1; scl_t<=1; phase<=2; end
                2: begin ack_err<=sda_i; phase<=3; end
                3: begin scl_o<=0; scl_t<=0; bit_cnt<=7; tx_byte<=CFG_BYTE;
                         phase<=0; state<=S_CD; end
            endcase

            S_CD: if (i2c_tick) case (phase)
                0: begin sda_o<=tx_byte[bit_cnt]; sda_t<=0; phase<=1; end
                1: begin scl_o<=1; scl_t<=1; phase<=2; end
                2: begin phase<=3; end
                3: begin scl_o<=0; scl_t<=0; phase<=0;
                   if (bit_cnt==0) state<=S_CDK; else bit_cnt<=bit_cnt-1; end
            endcase

            S_CDK: if (i2c_tick) case (phase)
                0: begin sda_t<=1; phase<=1; end
                1: begin scl_o<=1; scl_t<=1; phase<=2; end
                2: begin ack_err<=ack_err|sda_i; phase<=3; end
                3: begin scl_o<=0; scl_t<=0; phase<=0; state<=S_CP; end
            endcase

            // CONFIG STOP (SDA rises while SCL high)
            S_CP: if (i2c_tick) case (phase)
                0: begin sda_o<=0; sda_t<=0; phase<=1; end
                1: begin scl_o<=1; scl_t<=1; phase<=2; end
                2: begin sda_o<=1; sda_t<=1; phase<=3; end            // STOP
                3: begin ch_cnt<=0; phase<=0; state<=S_IDLE; end
            endcase

            // Wait for 256 Hz sample tick
            S_IDLE: begin
                scl_o<=1; scl_t<=1; sda_o<=1; sda_t<=1;
                if (smpl_tick) begin ch_cnt<=0; phase<=0; state<=S_RS; end
            end

            // READ - START
            S_RS: if (i2c_tick) case (phase)
                0: begin scl_o<=1; scl_t<=1; sda_o<=1; sda_t<=1; phase<=1; end
                1: begin sda_o<=0; sda_t<=0; phase<=2; end
                2: begin scl_o<=0; scl_t<=0; phase<=3; end
                3: begin bit_cnt<=7; tx_byte<=ADDR_R; phase<=0; state<=S_RA; end
            endcase

            // READ - send ADDR_R (7-bit addr + R=1)
            S_RA: if (i2c_tick) case (phase)
                0: begin sda_o<=tx_byte[bit_cnt]; sda_t<=0; phase<=1; end
                1: begin scl_o<=1; scl_t<=1; phase<=2; end
                2: begin phase<=3; end
                3: begin scl_o<=0; scl_t<=0; phase<=0;
                   if (bit_cnt==0) state<=S_RAK; else bit_cnt<=bit_cnt-1; end
            endcase

            S_RAK: if (i2c_tick) case (phase)
                0: begin sda_t<=1; phase<=1; end
                1: begin scl_o<=1; scl_t<=1; phase<=2; end
                2: begin ack_err<=ack_err|sda_i; phase<=3; end
                3: begin scl_o<=0; scl_t<=0; rx_h<=0; rx_l<=0;
                         bit_cnt<=7; phase<=0; state<=S_RH; end
            endcase

            // Receive high byte - shift in MSB first
            S_RH: if (i2c_tick) case (phase)
                0: begin sda_t<=1; phase<=1; end
                1: begin scl_o<=1; scl_t<=1; phase<=2; end
                2: begin rx_h<={rx_h[6:0], sda_i}; phase<=3; end
                3: begin scl_o<=0; scl_t<=0; phase<=0;
                   if (bit_cnt==0) state<=S_RHK; else bit_cnt<=bit_cnt-1; end
            endcase

            // Master ACK after byte 1 (more bytes coming)
            S_RHK: if (i2c_tick) case (phase)
                0: begin sda_o<=0; sda_t<=0; phase<=1; end            // ACK=low
                1: begin scl_o<=1; scl_t<=1; phase<=2; end
                2: begin phase<=3; end
                3: begin scl_o<=0; scl_t<=0; bit_cnt<=7; phase<=0; state<=S_RL; end
            endcase

            // Receive low byte
            S_RL: if (i2c_tick) case (phase)
                0: begin sda_t<=1; phase<=1; end
                1: begin scl_o<=1; scl_t<=1; phase<=2; end
                2: begin rx_l<={rx_l[6:0], sda_i}; phase<=3; end
                3: begin scl_o<=0; scl_t<=0; phase<=0;
                   if (bit_cnt==0) state<=S_RNACK; else bit_cnt<=bit_cnt-1; end
            endcase

            // Master NACK after byte 2 (signals end of read to slave)
            S_RNACK: if (i2c_tick) case (phase)
                0: begin sda_o<=1; sda_t<=0; phase<=1; end            // NACK=high
                1: begin scl_o<=1; scl_t<=1; phase<=2; end
                2: begin phase<=3; end
                3: begin scl_o<=0; scl_t<=0;
                         sample<={rx_h, rx_l};                        // latch word
                         phase<=0; state<=S_RP; end
            endcase

            // STOP
            S_RP: if (i2c_tick) case (phase)
                0: begin sda_o<=0; sda_t<=0; phase<=1; end
                1: begin scl_o<=1; scl_t<=1; phase<=2; end
                2: begin sda_o<=1; sda_t<=1; phase<=3; end
                3: begin phase<=0; state<=S_EMIT; end
            endcase

            // Push to AXI-S; loop back for remaining channels
            S_EMIT: begin
                if (!m_axis_tvalid || m_axis_tready) begin
                    m_axis_tdata  <= sample;          // [13:12]=CH, [11:0]=ADC
                    m_axis_tvalid <= 1;
                    m_axis_tlast  <= (ch_cnt==2'd3);
                    if (ch_cnt==2'd3) begin ch_cnt<=0; state<=S_IDLE; end
                    else begin ch_cnt<=ch_cnt+1; phase<=0; state<=S_RS; end
                end
            end

            default: state<=S_IDLE;
            endcase
        end
    end
endmodule

`timescale 1ns/1ps

// 128-tap symmetric FIR - 50 Hz notch, fs = 256 Hz
// Coefficients: Parks-McClellan, Q15 (scaled by 2^15 = 32768)
// Passband: 0-45 Hz, 55-128 Hz  Stopband: 47-53 Hz  Atten: >60 dB
//
// AXI-Stream slave in, AXI-Stream master out.
// tdata [15:0] = signed 16-bit sample (same word format as eeg_ad7991)
// tlast is passed through unchanged (end-of-4ch frame marker)
`timescale 1ns/1ps

module fir_notch_50hz (
    input  wire        aclk,
    input  wire        aresetn,
    input  wire [15:0] s_axis_tdata,
    input  wire        s_axis_tvalid,
    input  wire        s_axis_tlast,
    output wire        s_axis_tready,
    output reg  [15:0] m_axis_tdata,
    output reg         m_axis_tvalid,
    output reg         m_axis_tlast,
    input  wire        m_axis_tready
);
    localparam integer TAPS = 128;
    localparam integer HALF = 64;

    reg signed [15:0] dline [0:TAPS-1];
    reg signed [47:0] acc;
    reg [6:0] mac_idx;
    reg mac_busy;
    reg r_last;
    integer i;

    // --- COEFFS ---
    wire signed [15:0] coef [0:63];
    assign coef[0]=16'sd10;    assign coef[1]=16'sd15;    assign coef[2]=16'sd18;    assign coef[3]=16'sd14;
    assign coef[4]=16'sd2;     assign coef[5]=-16'sd18;   assign coef[6]=-16'sd42;   assign coef[7]=-16'sd66;
    assign coef[8]=-16'sd83;   assign coef[9]=-16'sd83;   assign coef[10]=-16'sd59;  assign coef[11]=-16'sd10;
    assign coef[12]=16'sd56;   assign coef[13]=16'sd122;  assign coef[14]=16'sd172;  assign coef[15]=16'sd188;
    assign coef[16]=16'sd159;  assign coef[17]=16'sd84;   assign coef[18]=-16'sd26;  assign coef[19]=-16'sd155;
    assign coef[20]=-16'sd270; assign coef[21]=-16'sd340; assign coef[22]=-16'sd336; assign coef[23]=-16'sd244;
    assign coef[24]=-16'sd72;  assign coef[25]=16'sd149;  assign coef[26]=16'sd366;  assign coef[27]=16'sd533;
    assign coef[28]=16'sd604;  assign coef[29]=16'sd549;  assign coef[30]=16'sd364;  assign coef[31]=16'sd72;
    assign coef[32]=-16'sd268; assign coef[33]=-16'sd596; assign coef[34]=-16'sd842; assign coef[35]=-16'sd944;
    assign coef[36]=-16'sd862; assign coef[37]=-16'sd589; assign coef[38]=-16'sd155; assign coef[39]=16'sd363;
    assign coef[40]=16'sd857;  assign coef[41]=16'sd1245; assign coef[42]=16'sd1460; assign coef[43]=16'sd1461;
    assign coef[44]=16'sd1238; assign coef[45]=16'sd815;  assign coef[46]=16'sd250;  assign coef[47]=-16'sd381;
    assign coef[48]=-16'sd989; assign coef[49]=-16'sd1467; assign coef[50]=-16'sd1729; assign coef[51]=-16'sd1726;
    assign coef[52]=-16'sd1448; assign coef[53]=-16'sd940; assign coef[54]=-16'sd282;  assign coef[55]=16'sd447;
    assign coef[56]=16'sd1135; assign coef[57]=16'sd1694; assign coef[58]=16'sd2045; assign coef[59]=16'sd2132;
    assign coef[60]=16'sd1936; assign coef[61]=16'sd1483; assign coef[62]=16'sd829;   assign coef[63]=16'sd32400;

    assign s_axis_tready = !mac_busy;

    // CRITICAL FOR ICARUS VERILOG: Zero memory at start
    initial begin
        for (i=0; i<TAPS; i=i+1) dline[i] = 0;
        mac_busy = 0;
        m_axis_tvalid = 0;
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            acc <= 0; mac_idx <= 0; mac_busy <= 0;
            m_axis_tvalid <= 0;
            for (i=0; i<TAPS; i=i+1) dline[i] <= 0; 
        end else begin
            if (m_axis_tvalid && m_axis_tready) m_axis_tvalid <= 0;

            if (!mac_busy) begin
                if (s_axis_tvalid) begin
                    for (i=TAPS-1; i>0; i=i-1) dline[i] <= dline[i-1];
                    // Subtract 2048 to remove DC offset from the 12-bit ADC
                    dline[0] <= $signed({4'b0, s_axis_tdata[11:0]}) - 16'sd2048;
                    acc <= 0; mac_idx <= 0; mac_busy <= 1; r_last <= s_axis_tlast;
                end
            end else begin
                acc <= acc + coef[mac_idx] * (dline[mac_idx] + dline[TAPS-1-mac_idx]);
                if (mac_idx == HALF-1) begin
                    mac_busy <= 0;
                    // Arithmetic shift and rounding
                    m_axis_tdata <= (acc + 48'sd16384) >>> 15;
                    m_axis_tvalid <= 1;
                    m_axis_tlast <= r_last;
                end else mac_idx <= mac_idx + 1;
            end
        end
    end
endmodule
`timescale 1ns/1ps

module kd240_eeg_top #(
    parameter CLK_FREQ    = 100_000_000,
    parameter SAMPLE_RATE = 256,
    parameter I2C_FREQ    = 400_000,
    parameter AD7991_ADDR = 7'h28
)(
    input  wire        s_axi_aclk,
    input  wire        s_axi_aresetn,     // active-low, from proc_sys_reset

    // I2C pads - single inout (IOBUF driven by Vivado or explicit below)
    inout  wire        j2_scl,            // Pmod J2 pin 1 - SCL
    inout  wire        j2_sda,            // Pmod J2 pin 2 - SDA

    // AXI4-Stream master → AXI DMA S2MM
    output wire [15:0] m_axis_tdata,
    output wire        m_axis_tvalid,
    output wire        m_axis_tlast,
    input  wire        m_axis_tready
);

    // -------------------------------------------------------------------------
    // I2C tristate wires
    // -------------------------------------------------------------------------
    wire scl_i, scl_o, scl_t;
    wire sda_i, sda_o, sda_t;

    // Xilinx IOBUF primitives - open-drain bidirectional
    IOBUF u_scl (.I(scl_o), .T(scl_t), .O(scl_i), .IO(j2_scl));
    IOBUF u_sda (.I(sda_o), .T(sda_t), .O(sda_i), .IO(j2_sda));

    // -------------------------------------------------------------------------
    // Internal AXI-Stream bus: acquisition → notch filter
    // -------------------------------------------------------------------------
    wire [15:0] acq_tdata;
    wire        acq_tvalid;
    wire        acq_tlast;
    wire        acq_tready;

    // -------------------------------------------------------------------------
    // Stage 1 - EEG I2C acquisition core
    // -------------------------------------------------------------------------
    eeg_ad7991_acquisition #(
        .CLK_FREQ   (CLK_FREQ),
        .SAMPLE_RATE(SAMPLE_RATE),
        .I2C_FREQ   (I2C_FREQ),
        .AD7991_ADDR(AD7991_ADDR)
    ) u_acq (
        .clk           (s_axi_aclk),
        .rst_n         (s_axi_aresetn),
        .scl_i         (scl_i),
        .scl_o         (scl_o),
        .scl_t         (scl_t),
        .sda_i         (sda_i),
        .sda_o         (sda_o),
        .sda_t         (sda_t),
        .m_axis_tdata  (acq_tdata),
        .m_axis_tvalid (acq_tvalid),
        .m_axis_tlast  (acq_tlast),
        .m_axis_tready (acq_tready)
    );

    // -------------------------------------------------------------------------
    // Stage 2 - 50 Hz FIR notch filter
    // -------------------------------------------------------------------------
    fir_notch_50hz u_notch (
        .aclk          (s_axi_aclk),
        .aresetn       (s_axi_aresetn),
        // slave port ← acquisition output
        .s_axis_tdata  (acq_tdata),
        .s_axis_tvalid (acq_tvalid),
        .s_axis_tlast  (acq_tlast),
        .s_axis_tready (acq_tready),
        // master port → DMA S2MM
        .m_axis_tdata  (m_axis_tdata),
        .m_axis_tvalid (m_axis_tvalid),
        .m_axis_tlast  (m_axis_tlast),
        .m_axis_tready (m_axis_tready)
    );

endmodule