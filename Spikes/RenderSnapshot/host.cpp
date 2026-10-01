#include "projection.hpp"
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdexcept>
using namespace render_experiment;
static std::vector<std::string> split(const std::string& line) {
    std::vector<std::string> result;
    std::istringstream stream(line); std::string part;
    while (std::getline(stream, part, '\t')) result.push_back(part);
    return result;
}
static std::string value(const ID& id) { return id.empty() ? "-" : id; }
static ID id(const std::string& text) { return text == "-" ? "" : text; }
static std::string list(const std::vector<ID>& values) {
    if (values.empty()) return "-";
    std::string result;
    for (const auto& item : values) { if (!result.empty()) result += ','; result += item; }
    return result;
}
int main() {
    // Private test subprocess transport, not a product ABI or file format.
    try {
        std::string line;
        if (!std::getline(std::cin, line)) throw std::runtime_error("header");
        const auto h = split(line);
        if (h.size() != 9 || h[0] != "H") throw std::runtime_error("header");
        Input input{{h[1], h[2], std::stoull(h[3])}, h[4], std::stod(h[5]), std::stod(h[6]), {}};
        while (std::getline(std::cin, line)) {
            if (line.empty()) continue;
            auto f = split(line);
            if (f.size() != 19 || f[0] != "N") throw std::runtime_error("row");
            InputNode n;
            n.id = id(f[1]); n.parent = id(f[2]); n.source = id(f[3]); n.kind = f[4];
            n.visible = f[5] == "1"; n.opacity = std::stod(f[6]); n.fill = std::stod(f[7]); n.blend = f[8];
            n.placement = {std::stod(f[9]), std::stod(f[10]), std::stod(f[11]), std::stod(f[12]), std::stod(f[13]),
                           f[14] == "1", f[15] == "1", f[16]};
            n.stylePresent = f[17] == "1"; n.enabledMaskPresent = f[18] == "1";
            input.nodes.push_back(std::move(n));
        }
        auto result = project(input, h[7], std::stoull(h[8]));
        if (result.error) {
            std::cout << "E\t" << result.error->code << '\t' << result.error->field << '\t' << value(result.error->id) << '\n';
            return 0; // Recoverable error is a result, not a host process failure.
        }
        const auto& data = result.snapshot->read();
        std::cout << std::setprecision(17);
        std::cout << "H\t" << data.publication.instance << '\t' << data.publication.state << '\t'
                  << data.publication.generation << '\t' << data.document << '\t' << data.width << '\t' << data.height << '\n';
        for (const auto& n : data.ordered) {
            const auto& p = n.own.placement; const auto& m = n.unitToDocument; const auto& b = n.axisBounds;
            std::cout << "N\t" << n.own.id << '\t' << value(n.own.parent) << '\t' << value(n.own.source) << '\t' << n.own.kind
                      << '\t' << n.depth << '\t' << n.own.visible << '\t' << n.effectiveVisible
                      << '\t' << n.own.opacity << '\t' << n.effectiveOpacity << '\t' << n.own.fill << '\t' << n.own.blend
                      << '\t' << n.clipping << '\t' << value(n.stackBase)
                      << '\t' << p.x << '\t' << p.y << '\t' << p.width << '\t' << p.height << '\t' << p.degrees
                      << '\t' << p.flipX << '\t' << p.flipY << '\t' << p.sampling << '\t' << n.own.stylePresent << '\t' << n.own.enabledMaskPresent
                      << '\t' << m.a << '\t' << m.b << '\t' << m.c << '\t' << m.d << '\t' << m.tx << '\t' << m.ty
                      << '\t' << b.x << '\t' << b.y << '\t' << b.width << '\t' << b.height
                      << '\t' << list(n.ancestors) << '\t' << list(n.maskAncestors) << '\t' << list(n.coverageChain) << '\n';
        }
        std::cout << "D\t" << list(data.drawn) << '\n';
    } catch (const std::bad_alloc&) { std::cout << "E\tallocationFailure\ttransport\t-\n"; }
    catch (const std::invalid_argument&) { std::cout << "E\tmalformedFixture\ttransport\t-\n"; }
    catch (const std::out_of_range&) { std::cout << "E\tmalformedFixture\ttransport\t-\n"; }
    catch (const std::runtime_error&) { std::cout << "E\tmalformedFixture\ttransport\t-\n"; }
    catch (const std::exception&) { std::cout << "E\tinternalFailure\ttransport\t-\n"; }
}
