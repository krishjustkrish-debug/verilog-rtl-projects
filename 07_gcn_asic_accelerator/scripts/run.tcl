############################################################
# INIT
############################################################
setLibraryUnit -time 1ps

set init_verilog "./GCN.syn.v"
set init_top_cell "GCN"
set init_design_netlisttype verilog
set init_sdc_file "./GCN_1.syn.sdc"

source ./Default.globals
init_design

############################################################
# FLOORPLAN (LARGE → avoids congestion)
############################################################
floorPlan -site coreSite -d 800 800 10 10 10 10
add_tracks -honor_pitch

############################################################
# POWER CONNECTION
############################################################
clearGlobalNets
globalNetConnect VDD -type pgpin -pin VDD -inst *
globalNetConnect VSS -type pgpin -pin VSS -inst *

addWellTap -cell TAPCELL_ASAP7_75t_R -cellInterval 150 -inRowOffset 10.564

############################################################
# PIN PLACEMENT (SAFE VERSION — NO FAILURES)
############################################################
set all_ports [dbGet top.terms.name]

puts "===================================="
puts "PORT LIST:"
puts $all_ports
puts "===================================="

setPinAssignMode -pinEditInBatch true

editPin -fixedPin 1 \
    -spreadType side \
    -edge 0 \
    -layer M4 \
    -pin $all_ports

setPinAssignMode -pinEditInBatch false

saveDesign GCN.pin.enc

############################################################
# PLACEMENT
############################################################
setPlaceMode -place_global_timing_effort medium
place_opt_design

############################################################
# CTS
############################################################
set_ccopt_property target_max_trans 50

ccopt_design

optDesign -postCTS
optDesign -postCTS -hold

saveDesign GCN.clock.enc

############################################################
# ROUTING
############################################################
setNanoRouteMode -routeTopRoutingLayer 3
setNanoRouteMode -routeBottomRoutingLayer 1
setNanoRouteMode -routeWithTimingDriven true

routeDesign -globalDetail

optDesign -postRoute -setup
optDesign -postRoute -hold
optDesign -postRoute -drv

############################################################
# VERIFY
############################################################
verifyConnectivity
verify_drc

############################################################
# REPORTS
############################################################
report_timing > GCN_postroute_timing.rpt
report_area   > GCN_area.rpt
report_power  > GCN_power.rpt

############################################################
# SAVE
############################################################
saveNetlist GCN.apr.v
saveDesign GCN.final.enc
