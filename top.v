`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:          V2 Retro Computing
// Engineer:         David Kuder
//
// Create Date:      12:50:08 04/16/2023
// Design Name:      picopal-v3
// Module Name:      top
// Project Name:     v2-analog-gs
// Target Devices:   xc9536xl and xc9572xl
// Tool versions:    Xilinx ISE 14.7
// Description:      CPLD Gateware for PicoPal v3 chip on the V2 Analog GS
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module top(
    input nLIRQ,
    input nMSBOE,
    input nLSBOE,
    input nDATAOE,
    input nDATADIR,
    output LRW,
    output nLSEL,
    input [7:0] LD,
    input nIOSEL,
    input nDEVSEL,
    input nIOSTROBE,
    input PHI0,
    input nM2SEL,
    input M2B0,
    input Q3,
    input M7Hz,
    input nWR,
    input nSYSRESET,
    output nIRQ,
    input INTIN,
    output INTOUT,
    input GS,
    input [3:0] E,
    output QP0
    );

reg [15:0] BUSADDR;
reg C8WINDOW;
reg C8WINDOWEXP;
reg M2B0LATCHED;
wire C8WINDOWSEL;
wire C1OVERLAY;
wire C2OVERLAY;
wire C4OVERLAY;
wire C5OVERLAY;

// Follow interrupt daisy chain rules
assign INTOUT = INTIN & nLIRQ;
assign nIRQ = !INTIN | nLIRQ;

// Qualify the PHI0 signal with /M2SEL if the GS jumper is closed
assign QP0 = PHI0 & (GS | !nM2SEL);

// $C800 window enabled and selected
assign C8WINDOWSEL = QP0 & C8WINDOW & !nIOSTROBE;

// Jumpers E[0:3] enable ROM overlays on other slots
assign C1OVERLAY = QP0 & E[0] & (BUSADDR[15:8] == 'hC1);
assign C2OVERLAY = QP0 & E[1] & (BUSADDR[15:8] == 'hC2);
assign C4OVERLAY = QP0 & E[2] & (BUSADDR[15:8] == 'hC4);
assign C5OVERLAY = QP0 & E[3] & (BUSADDR[15:8] == 'hC5);

// Tell the RP2040 when we are selected (Also abused for indicating M2B0 state if ADDR < $C000)
assign nLSEL = !M2B0LATCHED & !C1OVERLAY & !C2OVERLAY & !C4OVERLAY & !C5OVERLAY & nIOSEL & nDEVSEL & !C8WINDOWSEL;

// Abuse the XC95xxXL as a 5v to 3v level translator
// But (try to) make sure we won't answer any reads outside $Cxxx
assign LRW = nWR & !(BUSADDR[15:12] == 'hC);

// TODO: Swap control of the DATA Direction pin to the CPLD to free the pin on the RP2040?
// assign nDATADIR = nWR & !(BUSADDR[15:12] == 'hC) & !nLSEL;

initial begin
    C8WINDOW <= 'b0;
    C8WINDOWEXP <= 'b0;
end

// Capture the Address MSB as the bus transceivers are deselected
always @ (posedge nMSBOE)
begin
    BUSADDR[15:8] = LD[7:0];
end

// Capture the Address LSB as the bus transceivers are deselected
always @ (posedge nLSBOE)
begin
    BUSADDR[7:0] = LD[7:0];
end

// Capture the state of M2B0 at falling edge of Q3 while PHI0 is low
always @ (negedge Q3)
begin
    if(!PHI0) begin
        M2B0LATCHED <= M2B0;
    end
end

// Act on $C800 window select / deselect as the bus cycle ends or at reset
always @ (posedge nDATAOE or negedge nSYSRESET)
begin
    // Turn off $C800 window at system reset
    if(!nSYSRESET) begin
        C8WINDOW <= 'b0;
        C8WINDOWEXP <= 'b0;
    end else

    // Turn on the $C800 window if any of our ROM slots becomes active
    if(!nIOSEL | C1OVERLAY | C2OVERLAY | C4OVERLAY | C5OVERLAY) begin
        C8WINDOW <= 'b1;
    end else

    // $C800 window was marked to be disabled by a previous cycle, turn it off now.
    if(C8WINDOWEXP) begin
        C8WINDOW <= 'b0;
        C8WINDOWEXP <= 'b0;
    end else

    // End of cycle, we can turn off $C800 next cycle if $CFFF is being accessed.
    // This will allow writes to $CFFF to succeed (6502 Read/Write cycle nonsense)
    if(BUSADDR[15:0] == 'hCFFF) begin
        C8WINDOWEXP <= 'b1;
    end
end

endmodule
