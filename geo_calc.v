`timescale 1ns / 1ps
module top (
    input  wire CLK100MHZ,
    input  wire CPU_RESETN, 
    input  wire [9:0] SW,
    input  wire BTNU,
    input  wire BTND,
    output wire [2:0] LED,
    output wire [7:0] AN,  
    output wire [6:0] SEG,         
    output wire DP          
);
    wire clk = CLK100MHZ;
    wire rst = ~CPU_RESETN;

    wire [4:0]  a, b;
    wire        up_clean, dn_clean;
    wire        up_pulse, dn_pulse;
    wire [2:0]  sel;
    wire [19:0] result;
    wire [23:0] bcd;
    wire [31:0] digits;

    input_sync u_sync (.clk(clk), 
                       .rst(rst), 
                       .sw(SW), 
                       .a(a), 
                       .b(b)
    );

    debounce u_db_up (.clk(clk), .rst(rst), .btn(BTNU), .btn_clean(up_clean));
    debounce u_db_dn (.clk(clk), .rst(rst), .btn(BTND), .btn_clean(dn_clean));

    edge_det u_ed_up (.clk(clk), .rst(rst), .level(up_clean), .pulse(up_pulse));
    edge_det u_ed_dn (.clk(clk), .rst(rst), .level(dn_clean), .pulse(dn_pulse));

    mode_ctrl u_mode (
        .clk(clk), .rst(rst), .up(up_pulse), .dn(dn_pulse), .sel(sel)
    );

    geo_alu u_alu (
        .clk(clk), .rst(rst), .a(a), .b(b), .sel(sel), .result(result)
    );

    bin2bcd u_bcd (
        .clk(clk), .rst(rst), .bin(result), .bcd(bcd)
    );

    display_format u_fmt (
        .bcd(bcd), .sel(sel), .digits(digits)
    );

    ssd_mux u_ssd (
        .clk(clk), .rst(rst), .digits(digits), .an(AN), .seg(SEG), .dp(DP)
    );

    assign LED = sel;
endmodule



module input_sync (
    input  wire clk,
    input  wire rst,
    input  wire [9:0] sw,
    output wire [4:0] a,
    output wire [4:0] b
);
    reg [9:0] ff1, ff2;

    always @(posedge clk) begin
        if (rst) begin
            ff1 <= 10'd0;
            ff2 <= 10'd0;
        end else begin
            ff1 <= sw;
            ff2 <= ff1;
        end
    end

    assign a = ff2[4:0];
    assign b = ff2[9:5];
endmodule



module debounce #(
    parameter integer COUNT_MAX = 1_000_000   // 10 ms at 100 MHz
)(
    input  wire clk,
    input  wire rst,
    input  wire btn,
    output reg  btn_clean
);
    reg        s1, s2;
    reg [19:0] cnt;

    always @(posedge clk) begin
        if (rst) begin
            s1        <= 1'b0;
            s2        <= 1'b0;
            cnt       <= 20'd0;
            btn_clean <= 1'b0;
        end else begin
            s1 <= btn;
            s2 <= s1;

            if (s2 == btn_clean) begin
                cnt <= 20'd0;            
            end else if (cnt == COUNT_MAX - 1) begin
                btn_clean <= s2;            
                cnt <= 20'd0;
            end else begin
                cnt <= cnt + 20'd1;
            end
        end
    end
endmodule



module edge_det (
    input  wire clk,
    input  wire rst,
    input  wire level,
    output wire pulse
);
    reg prev;

    always @(posedge clk) begin
        if (rst) prev <= 1'b0;
        else     prev <= level;
    end

    assign pulse = level & ~prev;
endmodule



module mode_ctrl (
    input  wire       clk,
    input  wire       rst,
    input  wire       up,
    input  wire       dn,
    output reg  [2:0] sel
);
    always @(posedge clk) begin
        if (rst)            sel <= 3'd0;
        else if (up & ~dn)  sel <= sel + 3'd1;
        else if (dn & ~up)  sel <= sel - 3'd1;
    end
endmodule



module geo_alu (
    input  wire        clk,
    input  wire        rst,
    input  wire [4:0]  a,
    input  wire [4:0]  b,
    input  wire [2:0]  sel,
    output reg  [19:0] result
);
    wire [9:0] ab   = a * b;         // max 961
    wire [5:0] a_pb = a + b;         // max 62

    // each result is scaled x10 (one decimal place, truncated)
    wire [19:0] f0 = ab * 10;                // a*b      : rectangle area (square if b=a)
    wire [19:0] f1 = a_pb * 20;              // 2(a+b)   : perimeter
    wire [19:0] f2 = ab * 5;                 // a*b/2    : triangle area
    wire [19:0] f3 = (ab * 32170) >> 10;     // pi*a*b   : ellipse area (circle if b=a)
    wire [19:0] f4 = (a * 64340) >> 10;      // 2*pi*a   : circumference
    wire [19:0] f5 = ab * a * 10;            // a*a*b    : box volume (cube if b=a)
    wire [19:0] f6 = (ab * a * 32170) >> 10; // pi*a*a*b : cylinder volume
    wire [19:0] f7 = (ab * 64340) >> 10;     // 2*pi*a*b : cylinder curved surface

    reg [19:0] mux_out;

    always @(*) begin
        case (sel)
            3'd0:    mux_out = f0;
            3'd1:    mux_out = f1;
            3'd2:    mux_out = f2;
            3'd3:    mux_out = f3;
            3'd4:    mux_out = f4;
            3'd5:    mux_out = f5;
            3'd6:    mux_out = f6;
            3'd7:    mux_out = f7;
            default: mux_out = 20'd0;
        endcase
    end

    always @(posedge clk) begin
        if (rst) result <= 20'd0;
        else     result <= mux_out;
    end
endmodule



module bin2bcd (
    input  wire clk,
    input  wire rst,
    input  wire [19:0] bin,
    output reg  [23:0] bcd
);
    localparam [1:0] S_IDLE  = 2'd0,
                     S_SHIFT = 2'd1,
                     S_DONE  = 2'd2;

    reg [1:0] state;
    reg [4:0] cnt;
    reg [43:0] sh;      

    function [3:0] add3;
        input [3:0] d;
        begin
            add3 = (d >= 4'd5) ? (d + 4'd3) : d;
        end
    endfunction

    wire [23:0] adj = { add3(sh[43:40]), add3(sh[39:36]), add3(sh[35:32]), add3(sh[31:28]), add3(sh[27:24]), add3(sh[23:20]) };

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            cnt   <= 5'd0;
            sh    <= 44'd0;
            bcd   <= 24'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    sh    <= {24'd0, bin}; 
                    cnt   <= 5'd0;
                    state <= S_SHIFT;
                end

                S_SHIFT: begin
                    sh <= {adj, sh[19:0]} << 1;  
                    if (cnt == 5'd19) state <= S_DONE;
                    else              cnt   <= cnt + 5'd1;
                end

                S_DONE: begin
                    bcd   <= sh[43:20];      
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule



module display_format (
    input  wire [23:0] bcd,
    input  wire [2:0]  sel,
    output wire [31:0] digits
);
    localparam [3:0] CH_F     = 4'd10,
                     CH_BLANK = 4'd15;

    wire [3:0] d5 = bcd[23:20];
    wire [3:0] d4 = bcd[19:16];
    wire [3:0] d3 = bcd[15:12];
    wire [3:0] d2 = bcd[11:8];
    wire [3:0] d1 = bcd[7:4];  
    wire [3:0] d0 = bcd[3:0];   


    wire z5 = (d5 == 4'd0);
    wire z4 = z5 & (d4 == 4'd0);
    wire z3 = z4 & (d3 == 4'd0);
    wire z2 = z3 & (d2 == 4'd0);

    assign digits = { CH_F,
                      {1'b0, sel},
                      z5 ? CH_BLANK : d5,
                      z4 ? CH_BLANK : d4,
                      z3 ? CH_BLANK : d3,
                      z2 ? CH_BLANK : d2,
                      d1,
                      d0 };
endmodule



module ssd_mux #(
    parameter integer REFRESH_BITS = 20
)(
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] digits,
    output reg  [7:0]  an,
    output reg  [6:0]  seg,
    output wire        dp
);
    reg [REFRESH_BITS-1:0] refresh;

    always @(posedge clk) begin
        if (rst) refresh <= {REFRESH_BITS{1'b0}};
        else     refresh <= refresh + 1'b1;
    end

    wire [2:0] digit_sel = refresh[REFRESH_BITS-1 -: 3];

    wire [3:0] code = digits[digit_sel*4 +: 4];


    always @(*) begin
        an = 8'hFF;
        an[digit_sel] = 1'b0;
    end

    // decimal point only on digit 1
    assign dp = ~(digit_sel == 3'd1);


    always @(*) begin
        case (code)
            4'd0:    seg = 7'b1000000;
            4'd1:    seg = 7'b1111001;
            4'd2:    seg = 7'b0100100;
            4'd3:    seg = 7'b0110000;
            4'd4:    seg = 7'b0011001;
            4'd5:    seg = 7'b0010010;
            4'd6:    seg = 7'b0000010;
            4'd7:    seg = 7'b1111000;
            4'd8:    seg = 7'b0000000;
            4'd9:    seg = 7'b0010000;
            4'd10:   seg = 7'b0001110;   // F
            default: seg = 7'b1111111;
        endcase
    end
endmodule
