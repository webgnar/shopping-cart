class_name PavementLayer
extends Resource
## One layer of a pavement build-up (PavementBuildup), top to bottom: an asphalt course or an untreated aggregate
## base. Only the properties of its kind are used; defaults are 0, so a preset stores every value it uses. Each
## value should name its source in `source`; docs/ASPHALT_SCIENCE.md tracks which are sourced and which are still
## typical values.

enum Kind { ASPHALT, AGGREGATE }

@export var title := ""
@export var kind := Kind.ASPHALT
@export var thickness := 0.0                    ## m
@export_multiline var source := ""              ## where the thickness and properties come from

@export_group("Asphalt")
@export var stiffness_warm := 0.0               ## Pa: modulus on a mild day, when traffic bends it
@export var poisson := 0.0
@export var tensile_strength := 0.0             ## Pa: cold (-18 C) indirect tensile strength
@export var density := 0.0                      ## kg/m3 (bulk)
@export var binder_hpg := 0.0                   ## C: the binder's high performance grade (PG 64-22: 64); sets its ageing (BinderAgeing)

@export_group("Aggregate base")
@export var cohesion := 0.0                     ## Pa: Mohr-Coulomb cohesion (triaxial)
@export var friction_tan := 0.0                 ## tan of the friction angle
