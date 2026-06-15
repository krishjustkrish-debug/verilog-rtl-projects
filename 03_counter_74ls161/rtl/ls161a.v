module LS161a( 
    input [3:0] D,
    input CLK,
    input CLR_n,
    input LOAD_n,
    input ENP,
    input ENT,
    output reg [3:0] Q,
    output RCO
);

always @(posedge CLK or negedge CLR_n) begin 
    if (!CLR_n) 
        Q <= 4'b0000; 
    else if (!LOAD_n) 
        Q <= D; 
    else if (ENP && ENT) 
        Q <= Q + 1'b1; 
end 

assign RCO = ENT && (Q == 4'b1111);

endmodule
