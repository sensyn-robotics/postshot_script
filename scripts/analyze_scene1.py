"""Analyze scene 1 experiment results."""
import json, os, glob

base = 'C:/Postshot_Temp/lpips_scene1'
results = []
for qpath in sorted(glob.glob(os.path.join(base, 'output_*/postshot/quality.json'))):
    parts = qpath.replace(os.sep, '/').split('/')
    exp = [p for p in parts if p.startswith('output_')][0]

    ssim = json.load(open(qpath, encoding='utf-8-sig')).get('ssim', 0)

    sq_path = os.path.join(base, exp, 'colmap', 'sparse_quality.json')
    models = reg = total = reproj = 0
    if os.path.exists(sq_path):
        q = json.load(open(sq_path, encoding='utf-8-sig'))
        models = q['checks']['num_models']
        reg = q['checks']['registered_images']
        total = q['checks']['total_images']
        reproj = q['checks']['mean_reprojection_error']

    results.append((exp, models, reg, total, reproj, ssim))

results.sort(key=lambda x: x[5], reverse=True)
fmt = "{:<45} {:>3} {:>4}/{:<4} {:>7.3f} {:>6.3f}"
hdr = "{:<45} {:>3} {:>9} {:>7} {:>6}".format("Experiment", "Mod", "Reg", "Reproj", "SSIM")
print(hdr)
print("-" * 75)
for exp, models, reg, total, reproj, ssim in results:
    print(fmt.format(exp, models, reg, total, reproj, ssim))
