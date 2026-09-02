/// Visual scripting: a graph of nodes wired together, and the runtime that
/// walks it.
///
/// Two kinds of wire. An **exec** wire says what happens next, pushing forward
/// from an event; a **data** wire says where a value comes from, pulled
/// backward by whoever needs it. Every node type is written against that and
/// nothing else.
///
/// ```dart
/// final registry = standardVisualScriptRegistry();
/// final graph = readVisualScript(source);
/// final context = VisualScriptContext(graph: graph, host: myHost);
/// VisualScriptInterpreter(registry).fire(context, onTick.id);
/// ```
///
/// The graph and the standard node types are engine agnostic and pure Dart:
/// they reach the world only through a [VisualScriptHost], which is what lets the
/// same graph run in a test with a stub and in a scene with a renderer. The
/// scene-facing node types are registered by `package:flutter_scene/visual_script.dart`.
///
/// Import this only when a build needs scripting; the core
/// `package:scene/scene.dart` does not carry it.
library;

export 'src/visual_script/blueprint.dart'
    show
        Blueprint,
        BlueprintKind,
        BlueprintRunner,
        defaultBlueprintParent,
        defaultConstructionScriptName,
        defaultEventGraphName;
export 'src/visual_script/blueprint_source.dart'
    show
        BlueprintDiagnostic,
        BlueprintParseResult,
        blueprintEquivalent,
        blueprintSourceVersion,
        parseBlueprint,
        printBlueprint;
export 'src/visual_script/visual_script_control.dart'
    show
        breakLoop,
        cacheValue,
        casePin,
        casesOf,
        controlVisualScriptNodes,
        forEachLoop,
        forLoop,
        maxLoopIterations,
        nullCheck,
        nullCoalesce,
        once,
        selectValue,
        switchOnInteger,
        switchOnString,
        throwError,
        toggleFlow,
        toggleValue,
        tryCatch,
        whileLoop;
export 'src/visual_script/visual_script_data.dart'
    show
        addToList,
        clearList,
        dataVisualScriptNodes,
        dictionaryGet,
        dictionaryHas,
        dictionaryKeys,
        dictionaryRemove,
        dictionarySet,
        dictionaryValues,
        formatText,
        joinText,
        listContains,
        listCount,
        listItemAt,
        lowerCase,
        makeDictionary,
        makeList,
        mergeLists,
        removeFromList,
        replaceText,
        reverseList,
        splitText,
        textContains,
        textLength,
        textToNumber,
        trimText,
        upperCase,
        valueToText;
export 'src/visual_script/visual_script_graph.dart'
    show
        VisualScriptGraph,
        VisualScriptGraphKind,
        VisualScriptLink,
        VisualScriptNodeSpec,
        VisualScriptPin,
        VisualScriptType,
        VisualScriptVariable;
export 'src/visual_script/visual_script_json.dart'
    show
        decodeBlueprint,
        encodeBlueprint,
        readBlueprint,
        writeBlueprint,
        decodeVisualScript,
        encodeVisualScript,
        visualScriptVersion,
        readVisualScript,
        writeVisualScript;
export 'src/visual_script/visual_script_library.dart'
    show
        addNumbers,
        addVectors,
        andGate,
        branch,
        breakVector,
        clampNumber,
        defaultSignalName,
        delay,
        divideNumbers,
        doOnce,
        gate,
        getVariable,
        lerpNumber,
        makeVector,
        multiplyNumbers,
        notGate,
        numberGreaterThan,
        numberLessThan,
        numberNearlyEqual,
        onSignal,
        onStart,
        onTick,
        orGate,
        printValue,
        randomNumber,
        scaleVector,
        sequence,
        sequenceCountOf,
        sequencePin,
        setVariable,
        signalNameOf,
        sineWave,
        standardVisualScriptNodes,
        standardVisualScriptRegistry,
        subtractNumbers;
export 'src/visual_script/visual_script_math.dart'
    show
        absoluteNumber,
        angleBetween,
        arcTangent2,
        ceilNumber,
        combineRotations,
        cosineOf,
        crossProduct,
        degreesToRadians,
        distanceBetween,
        dotProduct,
        exclusiveOr,
        floorNumber,
        inverseLerp,
        invertRotation,
        lerpVector,
        makeRotation,
        mathVisualScriptNodes,
        maximumNumber,
        minimumNumber,
        moduloNumber,
        moveTowardsNumber,
        moveTowardsVector,
        multiplyVectors,
        negateNumber,
        normalizeVector,
        numberAtLeast,
        numberAtMost,
        numberInRange,
        powerNumber,
        projectOnVector,
        radiansToDegrees,
        randomBoolean,
        randomInteger,
        reflectVector,
        remapNumber,
        rotateVector,
        rotateVectorBy,
        roundNumber,
        signOfNumber,
        sineOf,
        slerpRotations,
        smoothStep,
        squareRoot,
        subtractVectors,
        tangentOf,
        valuesEqual,
        valuesNotEqual,
        vectorLength;
export 'src/visual_script/visual_script_trace.dart'
    show VisualScriptPinRef, VisualScriptTrace, VisualScriptTraceStep;
export 'src/visual_script/visual_script_runtime.dart'
    show
        VisualScriptBreak,
        VisualScriptContext,
        VisualScriptFlow,
        VisualScriptFlowStatus,
        VisualScriptFrame,
        VisualScriptGraphLookup,
        VisualScriptHost,
        VisualScriptInterpreter,
        VisualScriptNodeType,
        VisualScriptRegistry,
        VisualScriptResult,
        VisualScriptSignal,
        VisualScriptThrow,
        NullVisualScriptHost,
        scriptBool,
        scriptColor,
        scriptInteger,
        scriptList,
        scriptMap,
        scriptNumber,
        scriptQuaternion,
        scriptString,
        scriptVector,
        scriptVector2,
        scriptVector4;
