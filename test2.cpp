#include <vector>
#include <string>
#include <sstream>
#include <iomanip>

std::vector<std::string> parseCommandLine(const std::string& commandLine) {
    std::vector<std::string> args;
    std::istringstream iss(commandLine);
    std::string arg;

    while (iss >> std::quoted(arg)) {
        args.push_back(arg);
    }

    return args;
}

int main() {
    std::string commandLine = "cmd.exe /C date /T \"foo \\\" bar\"";
    std::vector<std::string> args = parseCommandLine(commandLine);
    for (auto& arg : args) {
        printf("%s\n", arg.c_str());
    }
    return 0;
}