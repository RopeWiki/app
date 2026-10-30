# Importing pages with `ropewiki-import` (Special:Export files): the templates, properties and
# queries of the imported pages must work. The fixture is made up (fixtures/canyon.xml); to check a
# real page, export it from the live site with "Include templates" and add `ropewiki-import` of it
# below, then read Special:WantedTemplates / WantedPages / WantedProperties for what is missing.
#
#   nix build .#checks.x86_64-linux.import
{
  name = "ropewiki-import";

  nodes.machine =
    { ... }:
    {
      imports = [ ../vm/dev-site.nix ];
      services.ropewiki = {
        enable = true;
        search.enable = false;
      };
      virtualisation.memorySize = 2048;
    };

  testScript = ''
    import json
    import re

    def get(path):
        return machine.succeed(f"curl --fail --silent --insecure 'https://localhost{path}'")

    def ask(query):
        out = machine.succeed(
            "curl --fail --silent --insecure --get https://localhost/api.php "
            f"--data-urlencode action=ask --data-urlencode 'query={query}' --data-urlencode format=json"
        )
        return json.loads(out)["query"]["results"]

    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("ropewiki-pages.service")
    machine.wait_for_open_port(443)

    with subtest("the development site has a sysop login, Admin / admin"):
        machine.wait_for_unit("ropewiki-dev-admin.service")
        api = "curl --fail --silent --insecure -c /tmp/jar -b /tmp/jar https://localhost/api.php"
        token = json.loads(machine.succeed(f"{api} '--get' --data-urlencode action=query --data-urlencode meta=tokens --data-urlencode type=login --data-urlencode format=json"))["query"]["tokens"]["logintoken"]
        login = json.loads(machine.succeed(
            f"{api} --data-urlencode action=login --data-urlencode lgname=Admin --data-urlencode lgpassword=admin "
            f"--data-urlencode 'lgtoken={token}' --data-urlencode format=json"))
        assert login["login"]["result"] == "Success", login
        info = json.loads(machine.succeed(f"{api} --get --data-urlencode action=query --data-urlencode meta=userinfo --data-urlencode uiprop=groups --data-urlencode format=json"))
        assert {"sysop", "bureaucrat"} <= set(info["query"]["userinfo"]["groups"]), info

    with subtest("a missing file or script is an error"):
        machine.fail("ropewiki-import")
        machine.fail("ropewiki-import /nonexistent.xml")
        machine.fail("ropewiki-maintenance noSuchScript.php")

    with subtest("the fixture imports"):
        assert machine.succeed("curl --silent --insecure -o /dev/null -w '%{http_code}' 'https://localhost/Fixture_Creek_(Middle_Fork)'") == "404"
        machine.copy_from_host("${./fixtures/canyon.xml}", "/tmp/canyon.xml")
        machine.succeed("ropewiki-import /tmp/canyon.xml")

    with subtest("the page renders its template"):
        page = get("/Fixture_Creek_(Middle_Fork)")
        assert "Rating" in page and "Fixture Creek (Lower)" in page, page[:3000]
        # a template that does not exist is rendered as a red link ("new") to it
        assert not re.search(r'class="new"[^>]*title="Template:', page), "the template is missing"
        assert "Fixture canyons" in page  # the category the template adds

    with subtest("properties are typed and queries run: the Property: page was imported and applied"):
        # With type "Page" the comparison would be alphabetical and "10" > "2" false; as a Number it is true.
        hits = ask("[[Category:Fixture canyons]][[Has rating::>2]]|?Has rating")
        assert list(hits) == ["Fixture Creek (Middle Fork)"], hits
        assert ask("[[Category:Fixture canyons]]|?Has rating").keys() == {"Fixture Creek (Middle Fork)", "Fixture Creek (Lower)"}

    with subtest("the #ask on the page itself lists the match"):
        page = get("/Fixture_Creek_(Middle_Fork)")
        assert page.count("Fixture Creek (Middle Fork)") >= 2, "the #ask result list is empty"

    with subtest("a real page, exported from the live site with its templates, renders"):
        machine.copy_from_host("${./fixtures/lytle-creek.xml}", "/tmp/lytle-creek.xml")
        out = machine.succeed("ropewiki-import /tmp/lytle-creek.xml 2>&1")
        # the page's Lua modules run while the import rebuilds its data; the tools they call must exist
        assert "command not found" not in out, out
        page = get("/Lytle_Creek_(Middle_Fork)")
        # what the page links to that does not exist, grouped by namespace (the export only has
        # templates and modules: properties, categories, forms and files are not in it)
        missing = sorted(set(re.findall(r'class="new"[^>]*title="([^"]*?) \(page does not exist\)"', page)))
        errors = re.findall(r'(Lua error[^<]*|Script error[^<]*|Template loop[^<]*|Expression error[^<]*|Parser function[^<]*)', page)
        assert "Introduction" in page and "Lytle Creek Road" in page, "the page text is missing"
        facts = json.loads(get("/api.php?action=browsebysubject&subject=Lytle_Creek_(Middle_Fork)&format=json"))
        props = sorted(p["property"] for p in facts["query"]["data"])
        for name in ["Has_coordinates", "Located_in_region", "Has_info_rating"]:
            assert name in props, f"{name} not stored: {props}"
        assert not [t for t in missing if t.startswith(("Template:", "Module:"))], missing
        assert not errors, errors

    with subtest("importing again is harmless and no unit has failed"):
        machine.succeed("ropewiki-import /tmp/canyon.xml")
        assert machine.succeed("systemctl --failed --no-legend").strip() == ""
  '';
}
