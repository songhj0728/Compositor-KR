"""Exercise the private Mac-test subprocess transport against the real host."""
import subprocess
import sys
import unittest

HOST = sys.argv.pop()


def row(identity, parent="-", source="-", kind="empty", visible="1", opacity="1", fill="1"):
    return "\t".join(["N", identity, parent, source, kind, visible, opacity, fill,
                      "Normal", "0", "0", "8", "8", "0", "0", "0", "High quality", "0", "0"])


def project(rows, generation="7", expected="7"):
    header = f"H\tinstance\tstate\t{generation}\tdocument\t100\t80\tinstance\t{expected}\n"
    result = subprocess.run([HOST], input=header + "\n".join(rows) + "\n", text=True,
                            capture_output=True, check=True)
    return [line.split("\t") for line in result.stdout.splitlines()]


class TransportTests(unittest.TestCase):
    def test_bulk_order_and_values(self):
        lines = project([row("leaf", "group", opacity="0.3", fill="0.2"),
                         row("group", kind="group", opacity="0.5")])
        nodes = [line for line in lines if line[0] == "N"]
        self.assertEqual([node[1] for node in nodes], ["group", "leaf"])
        self.assertTrue(all(len(node) == 37 for node in nodes))
        self.assertAlmostEqual(float(nodes[1][9]), 0.15)
        self.assertAlmostEqual(float(nodes[1][10]), 0.2)
        self.assertEqual(lines[-1], ["D", "leaf"])

    def test_hidden_source_survives_reorder(self):
        nodes = project([row("child", source="base"), row("base", visible="0")])
        child = nodes[1]
        self.assertEqual(child[7], "1")
        self.assertEqual(child[12], "independent")
        self.assertEqual(child[36], "base")
        self.assertEqual(nodes[2][1], "base")

    def test_domain_errors_are_results(self):
        for rows, code in [([row("a"), row("a")], "duplicateID"),
                           ([row("a", parent="missing")], "missingParent"),
                           ([row("a", source="a")], "clippingCycle")]:
            with self.subTest(code=code):
                self.assertEqual(project(rows)[0][0:2], ["E", code])
        self.assertEqual(project([row("a")], expected="8")[0][0:2], ["E", "stalePublication"])

    def test_empty_bulk_document(self):
        self.assertEqual(project([])[-1], ["D", "-"])

    def test_malformed_fixture_is_recoverable(self):
        result = subprocess.run([HOST], input="not-a-header\n", text=True, capture_output=True, check=True)
        self.assertEqual(result.stdout.split("\t")[0:2], ["E", "malformedFixture"])


if __name__ == "__main__":
    unittest.main()
