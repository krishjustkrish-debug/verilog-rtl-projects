`timescale 1ns/1ps

module ls161a_tb;

    reg [3:0] D;
    reg CLK;
    reg CLR_n;
    reg LOAD_n;
    reg ENP;
    reg ENT;

    wire [3:0] Q;
    wire RCO;

    LS161a dut (
        .D(D),
        .CLK(CLK),
        .CLR_n(CLR_n),
        .LOAD_n(LOAD_n),
        .ENP(ENP),
        .ENT(ENT),
        .Q(Q),
        .RCO(RCO)
    );

    always #5 CLK = ~CLK;

    initial begin
        CLK = 0;
        D = 4'b0000;
        CLR_n = 1'b1;
        LOAD_n = 1'b1;
        ENP = 1'b0;
        ENT = 1'b0;

        // Asynchronous reset
        #3;
        CLR_n = 1'b0;
        #10;
        CLR_n = 1'b1;

        // Parallel load
        D = 4'b1010;
        LOAD_n = 1'b0;
        #10;
        LOAD_n = 1'b1;

        // Count enable
        ENP = 1'b1;
        ENT = 1'b1;
        repeat (8) #10;

        // Hold condition
        ENP = 1'b0;
        repeat (3) #10;

        // Count again to test rollover and RCO
        ENP = 1'b1;
        ENT = 1'b1;
        repeat (10) #10;

        $finish;
    end

    initial begin
        $monitor("Time=%0t D=%b CLR_n=%b LOAD_n=%b ENP=%b ENT=%b Q=%b RCO=%b",
                 $time, D, CLR_n, LOAD_n, ENP, ENT, Q, RCO);
    end

endmodule
