// Applies re/symbols.txt (lines: "<hex address> <name>") to the current program.
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.SourceType;
import java.nio.file.*;

public class ApplySymbols extends GhidraScript {
	public void run() throws Exception {
		for (String line : Files.readAllLines(Paths.get(getScriptArgs()[0]))) {
			line = line.strip();
			if (line.isEmpty() || line.startsWith("#")) continue;
			String[] p = line.split("\\s+");
			Address a = toAddr(Long.decode(p[0]));
			Function f = getFunctionAt(a);
			if (f != null) f.setName(p[1], SourceType.USER_DEFINED);
			else createLabel(a, p[1], true, SourceType.USER_DEFINED);
		}
	}
}
