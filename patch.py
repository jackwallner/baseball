import yaml
with open("project.yml", "r") as f:
    data = yaml.safe_load(f)
data["targets"]["StatScoutTests"]["settings"] = {"base": {"GENERATE_INFOPLIST_FILE": "YES"}}
with open("project.yml", "w") as f:
    yaml.dump(data, f, sort_keys=False)
