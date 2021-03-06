library(Seurat)
library(tidyverse)
library(qs)
library(scAlign)

# Env variables -----------------------------------------------------------
brad_dir = Sys.getenv("BRAD_HOME")
print(brad_dir)
# Directories -------------------------------------------------------------

dir_root = file.path(brad_dir, "data2/rstudio/birds/scRNA")
dev_dir = file.path(dir_root, "devin_combined", "finch_cells")
dev_data_dir = file.path(dir_root, "devin_combined", "data")
dev_out = file.path(dev_dir, "preprocessing", "integrate", "zf_bf", "joint2", "SCT", "song")
dev_out_sub_dir = file.path(dev_out, sprintf("anchor%s_filter%s_score%s_maxfeatures%s_dims%s", 5, 200, 30, 200, 30))

out_dir = file.path(dev_dir, "comparative", "integrated")
script_name = "comparative_zeisel_forebrain_zf_scalign_gaba_prep"
out_dir = file.path(out_dir, script_name)
dir.create(out_dir, recursive=T)

## Data dir
tree_dir = file.path(dev_dir, "trees")
script_data_name = "celltypes_hclust_gaba_int_sub2"
tree_dir = file.path(tree_dir, script_data_name)
data_out_obj_fname = file.path(tree_dir, "obj_integrated_subclustered_gaba.qs")
data_out_obj_redo_fname = file.path(out_dir, "obj_integrated_subclustered_gaba_SCT.qs")

## Markers
assay_to_use = "SCT"
markers_fname = file.path(dev_out_sub_dir, sprintf("marker_genes_cluster_int_sub2_gaba_%s.rds", assay_to_use))

## Compare dir
loom_data_dir = file.path(brad_dir, "data/scrna_datasets/zeisel_2018/")
compare_prefix = "l6_r2_cns_neurons_seurat"

# Finch data ---------------------------------------------------------------
cat("Load finch data...\n")
redo = T
if (redo) {
  obj_int_filt = qread(data_out_obj_fname)
  obj_int_filt = subset(obj_int_filt, subset=species=="zf")
  obj_int_filt = SCTransform(obj_int_filt, 
                             assay="RNA",
                             vars.to.regress = c("percent.mito", 
                                                 
                                                 "position2"),
                             return.only.var.genes = F
  )
  qsave(obj_int_filt, data_out_obj_redo_fname)
} else {
  obj_int_filt = qread(data_out_obj_redo_fname)
}

# Compare data --------------------------------------------------------------------

cat("Load compare data...\n")
compare_prefix1 = "l6_r2_cns_neurons_seurat_GABA_Acetyl_forebrain"


compare_sub_fname = file.path(loom_data_dir, sprintf("%s.qs", compare_prefix1))

redo = F
if (redo) {
  obj_fname = file.path(loom_data_dir, sprintf("%s.qs", compare_prefix))
  zei_obj_in = qread(obj_fname)
  zei_obj_in$idents = Idents(zei_obj_in)
  nt_select = "GABA|Acetyl"
  cells = Cells(zei_obj_in)[grepl(nt_select, zei_obj_in$Neurotransmitter)]
  
  
  zei_obj_in1 = subset(zei_obj_in, cells=cells)
  
  regions_to_use = c("Hippocampus,Cortex",
                     "Hippocampus",
                     "Olfactory bulb",
                     "Striatum dorsal",
                     "Striatum ventral",
                     "Striatum dorsal, Striatum ventral",
                     "Striatum dorsal, Striatum ventral,Amygdala",
                     "Pallidum")
  cells = Cells(zei_obj_in1)[zei_obj_in1$Region %in% regions_to_use]
  zei_obj_in1 = subset(zei_obj_in1, cells=cells)
  rm(zei_obj_in)
  
  options(future.globals.maxSize=10000 * 1024^2)
  plan(multiprocess(workers=3, gc=T))
  zei_obj_in1 = SCTransform(zei_obj_in1, vars.to.regress = c("MitoRiboRatio"))
  qsave(zei_obj_in1, compare_sub_fname)
} else {
  zei_obj_in1 = qread(compare_sub_fname)
}


# Create object ------------------------------------------------------------
cat("Create object...\n")
fname_int = file.path(out_dir, "obj_scalign.qs")

res_to_use = "cluster_int_sub2"
zei_obj_in1$dataset = "zeisel_2018"
obj_int_filt$dataset = "finch"

zei_obj_in1$species = "mouse"

zei_obj_in1$celltype_comb = zei_obj_in1$idents
obj_int_filt$celltype_comb = FetchData(obj_int_filt, res_to_use)

objs = c(obj_int_filt, zei_obj_in1)  
objs = map(objs, function(x) {
  DefaultAssay(x) = "SCT"
  x
})

common_features = Reduce(intersect, map(objs, ~rownames(.x)))
common_cols = c("celltype_comb", "species", "dataset")
objs = map(objs, function(x) {
  x = x[common_features, ]
  md = FetchData(x, common_cols)
  x@meta.data = md
  x
})

assay_to_use = "SCT"
var_genes = SelectIntegrationFeatures(objs, assay=rep(assay_to_use, times=length(objs)))

objs_sce = map(objs, function(x) {
  md = FetchData(x, c("species", "dataset", "celltype_comb"))
  sce = SingleCellExperiment(
    assays = list(counts = as.matrix(GetAssayData(x, assay=assay_to_use, slot="counts")[var_genes,]),
                  logcounts = as.matrix(GetAssayData(x, assay=assay_to_use, slot="data")[var_genes,])#,
                  #scale.data = GetAssayData(x, assay=assay_to_use, slot="scale.data")[var_genes,]
		  ),
    colData = DataFrame(md)
)
  
})

  sca = scAlignCreateObject(sce.objects = objs_sce,
                                  genes.use = var_genes,
                                  data.use="logcounts",
                                  cca.reduce = TRUE,
                                  ccs.compute = 40,
                                  project.name = "joint_align")

qsave(sca, fname_int)

